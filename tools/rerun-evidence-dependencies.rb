#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tempfile"
require "tmpdir"
require "time"
require_relative "lib/evidence_dependency_graph"

root = EvidenceDependencyGraph::ROOT
labs = %w[
  authority-lock definitive-inventory sql-surface sql types-constraints catalog-inventory
  partitioning extension security mvcc locking deadlock planner statistics index performance
  wal backup-recovery pitr replication logical-replication observability maintenance
  failure-injection migration upgrade pg-upgrade compatibility-matrix reference-system
]
commands = labs.map { |lab| ["lab:#{lab}", ["bash", "scripts/run-lab.sh", lab]] } + [
  ["static-gates", ["make", "test-static"]],
  ["skill-eval", ["make", "eval"]],
  ["scenario-runtime", ["ruby", "tools/run-scenario-security-001.rb"]],
  ["scenario-proofs", ["ruby", "tools/generate-scenario-proofs.rb"]],
  ["scenario-closure-plan", ["ruby", "tools/generate-scenario-closure-plan.rb"]],
  ["provenance", ["ruby", "tools/generate-provenance.rb"]]
]

excluded_tree_path = lambda do |relative|
  relative == ".git" || relative.start_with?(".git/") ||
    relative == ".cache" || relative.start_with?(".cache/")
end

tree_state = lambda do |directory|
  Dir.glob(File.join(directory, "**", "*"), File::FNM_DOTMATCH).each_with_object({}) do |path, state|
    relative = path.delete_prefix("#{directory}/")
    next if relative.empty? || relative.end_with?("/.", "/..") || excluded_tree_path.call(relative)
    next unless File.file?(path)

    state[relative] = "sha256:#{Digest::SHA256.file(path).hexdigest}"
  end
end

generated_path = lambda do |relative|
  relative == "provenance.yaml" || relative == EvidenceDependencyGraph::LEDGER_PATH ||
    relative.start_with?("evidence/", "artifacts/", "evals/")
end

stage_input_digest = lambda do |stage_root, members|
  EvidenceDependencyGraph.digest_canonical(members.sort.map do |relative|
    path = File.join(stage_root, relative)
    raise "Staging inputがありません: #{relative}" unless File.file?(path)

    {"path"=>relative, "digest"=>"sha256:#{Digest::SHA256.file(path).hexdigest}"}
  end)
end

atomic_replace = lambda do |source, destination|
  FileUtils.mkdir_p(File.dirname(destination))
  Tempfile.create(["evidence-publish", File.extname(destination)], File.dirname(destination)) do |temp|
    File.open(source, "rb") { |input| IO.copy_stream(input, temp) }
    temp.flush
    temp.fsync
    File.chmod(File.stat(source).mode & 0o777, temp.path)
    temp.close
    File.rename(temp.path, destination)
  end
end

publish_generation = lambda do |stage_root, relative_paths|
  Dir.mktmpdir("postgresql-evidence-publish-backup-") do |backup_root|
    existing = {}
    relative_paths.each do |relative|
      destination = File.join(root, relative)
      next unless File.file?(destination)

      existing[relative] = true
      backup = File.join(backup_root, relative)
      FileUtils.mkdir_p(File.dirname(backup))
      FileUtils.cp(destination, backup, preserve: true)
    end

    published = []
    begin
      relative_paths.each do |relative|
        atomic_replace.call(File.join(stage_root, relative), File.join(root, relative))
        published << relative
      end
    rescue StandardError
      published.reverse_each do |relative|
        destination = File.join(root, relative)
        if existing[relative]
          atomic_replace.call(File.join(backup_root, relative), destination)
        else
          File.delete(destination) if File.file?(destination)
        end
      end
      raise
    end
  end
end

observed_at = Time.now.utc.iso8601(6)
input_specs = EvidenceDependencyGraph.current_input_bindings
bindings = input_specs.map { |input| {"input_id"=>input.fetch("id"), "digest"=>input.fetch("digest")} }

Dir.mktmpdir("postgresql-evidence-rerun-") do |temporary_root|
  stage_root = File.join(temporary_root, "repository")
  FileUtils.mkdir_p(stage_root)
  Dir.children(root).sort.each do |entry|
    next if %w[.git .cache].include?(entry)

    FileUtils.cp_r(File.join(root, entry), stage_root, preserve: true)
  end

  input_specs.each do |input|
    actual = stage_input_digest.call(stage_root, input.fetch("members"))
    abort "Staging copyの入力digestが一致しません: #{input.fetch('id')}" unless actual == input.fetch("digest")
  end
  before = tree_state.call(stage_root)
  started_at = Time.now.utc.iso8601(6)
  commands.each_with_index do |(label, argv), index|
    puts format("[%02d/%02d] %s", index + 1, commands.length, label)
    success = system(*argv, chdir: stage_root)
    abort "Evidence dependency rerun failed on first attempt: #{label}; prior generation retained" unless success
  end
  completed_at = Time.now.utc.iso8601(6)

  input_specs.each do |input|
    actual = stage_input_digest.call(stage_root, input.fetch("members"))
    abort "Rerun中に入力が変化しました: #{input.fetch('id')}" unless actual == input.fetch("digest")
  end
  docker_version, = Open3.capture2("docker", "--version")
  ledger = {
    "schema_version"=>1,
    "id"=>"postgresql-evidence-rerun-#{Time.parse(started_at).utc.strftime('%Y%m%dt%H%M%Sz')}",
    "command"=>"ruby tools/rerun-evidence-dependencies.rb",
    "observed_at"=>observed_at,
    "started_at"=>started_at,
    "completed_at"=>completed_at,
    "result"=>"passed",
    "attempts"=>1,
    "runtime_identity"=>{
      "server"=>"PostgreSQL 18.6 (plus PostgreSQL 17.11 for compatibility/upgrade)",
      "client"=>"psql from pinned PostgreSQL container images",
      "container_engine"=>docker_version.strip,
      "host_platform"=>RUBY_PLATFORM,
      "profiles"=>%w[local container cluster]
    },
    "input_bindings"=>bindings,
    "commands"=>commands.map { |label, argv| {"id"=>label, "argv"=>argv, "attempts"=>1, "result"=>"passed"} }
  }
  stage_ledger = File.join(stage_root, EvidenceDependencyGraph::LEDGER_PATH)
  FileUtils.mkdir_p(File.dirname(stage_ledger))
  File.write(stage_ledger, JSON.pretty_generate(ledger) + "\n")

  after = tree_state.call(stage_root)
  removed = before.keys - after.keys
  abort "Rerunが既存fileを削除しました: #{removed.first}" unless removed.empty?
  changed = after.keys.select { |relative| before[relative] != after[relative] }.sort
  unexpected = changed.reject { |relative| generated_path.call(relative) }
  abort "RerunがEvidence範囲外を変更しました: #{unexpected.first}" unless unexpected.empty?
  abort "Rerunは公開対象Evidenceを生成しませんでした" if changed.empty?

  publish_generation.call(stage_root, changed)
  puts "Staged Evidence generationをrollback付きで公開しました: #{changed.length} files"
end
puts "Evidence dependency full rerun passed on first attempt: #{commands.length} commands; prior generation retained until full pass"
