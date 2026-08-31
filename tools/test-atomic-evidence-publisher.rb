#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "lib/atomic_evidence_publisher"

def write_tree(root, label, partial: false)
  FileUtils.mkdir_p(File.join(root, "traces"))
  File.write(File.join(root, "results.json"), JSON.generate("generation"=>label) + "\n")
  File.write(File.join(root, "traces", "#{label}.trace"), "#{label}-trace\n")
  return if partial

  FileUtils.mkdir_p(File.join(root, "metrics"))
  File.write(File.join(root, "metrics", "#{label}.json"), JSON.generate("generation"=>label) + "\n")
end

def snapshot(root)
  Dir.glob(File.join(root, "**/*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort.to_h do |path|
    [path.delete_prefix("#{root}/"), Digest::SHA256.file(path).hexdigest]
  end
end

validator = lambda do |root|
  required = ["results.json", "metrics/new.json"]
  missing = required.reject { |relative| File.file?(File.join(root, relative)) }
  raise AtomicEvidencePublisher::PublicationError, "incomplete staged generation: #{missing.join(', ')}" unless missing.empty?
end

Dir.mktmpdir("postgresql-atomic-evidence-") do |tmp|
  output = File.join(tmp, "pattern-scenarios")
  write_tree(output, "old")
  baseline = snapshot(output)

  publisher = AtomicEvidencePublisher.new(output, validator: validator)
  result = publisher.publish(run_status: "failed") { |staging| write_tree(staging, "new") }
  abort "failed run removed or changed prior success" unless result == :retained_prior_success && snapshot(output) == baseline
  abort "failed run leaked staging directories" if Dir.exist?(publisher.staging_root) || Dir.exist?(publisher.backup_root)

  result = publisher.publish(run_status: "failed") { |staging| write_tree(staging, "new", partial: true) }
  abort "partial failed run removed or changed prior success" unless result == :retained_prior_success && snapshot(output) == baseline
  abort "partial failed run leaked staging directories" if Dir.exist?(publisher.staging_root) || Dir.exist?(publisher.backup_root)

  begin
    publisher.publish(run_status: "passed") do |staging|
      write_tree(staging, "new")
      raise "oracle failed before publish"
    end
    abort "oracle failure was not raised"
  rescue RuntimeError => e
    raise unless e.message == "oracle failed before publish"
    abort "oracle failure changed prior success digests" unless snapshot(output) == baseline
    abort "oracle failure leaked staging directories" if Dir.exist?(publisher.staging_root) || Dir.exist?(publisher.backup_root)
  end

  begin
    publisher.publish(run_status: "passed") do |staging|
      write_tree(staging, "new", partial: true)
    end
    abort "partial staged generation was published"
  rescue AtomicEvidencePublisher::PublicationError
    abort "partial generation changed prior success" unless snapshot(output) == baseline
    abort "partial generation leaked staging directories" if Dir.exist?(publisher.staging_root) || Dir.exist?(publisher.backup_root)
  end

  %i[before_promote after_promote].each do |failpoint|
    begin
      publisher.publish(run_status: "passed", failpoint: failpoint) { |staging| write_tree(staging, "new") }
      abort "swap failure was not raised: #{failpoint}"
    rescue AtomicEvidencePublisher::PublicationError
      abort "swap rollback did not restore prior success: #{failpoint}" unless snapshot(output) == baseline
      abort "swap rollback leaked staging directories: #{failpoint}" if Dir.exist?(publisher.staging_root) || Dir.exist?(publisher.backup_root)
    end
  end

  result = publisher.publish(run_status: "passed") { |staging| write_tree(staging, "new") }
  current = snapshot(output)
  abort "full pass was not published" unless result == :published
  abort "new and old generations were mixed" unless current.keys.sort == %w[metrics/new.json results.json traces/new.trace]
  abort "temporary swap directories leaked" if Dir.exist?(publisher.staging_root) || Dir.exist?(publisher.backup_root)
end

puts "Verified atomic Scenario Evidence publication: failed/partial/oracle-error runs retain prior success, swap failures roll back, successful generations do not mix."
