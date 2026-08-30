# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "tmpdir"

require_relative "evidence_dependency_graph"

module TrackedGeneratedFreshness
  ROOT = File.expand_path("../..", __dir__)
  EXCLUDED_ROOT_ENTRIES = %w[.git .cache].freeze
  PROFILES = {
    "static-gates"=>{
      "commands"=>[
        ["bash", "scripts/static-gates.sh"]
      ],
      "paths"=>%w[
        evidence/artifacts/foundation-authority-lock.json
        evidence/artifacts/publication-static-gates.json
        evidence/foundation-authority-lock.evidence.yaml
        evidence/publication-static-gates.evidence.yaml
        evidence/harnesses/foundation-authority-lock.manifest
        evidence/harnesses/publication-static-gates.manifest
      ]
    },
    "eval"=>{
      "commands"=>[
        ["bash", "evals/run.sh"]
      ],
      "paths"=>%w[
        evidence/artifacts/skill-router-eval.json
        evidence/skill-router-eval.evidence.yaml
        evidence/harnesses/skill-router-eval.manifest
        evals/postgresql-router.skill-eval.json
        evals/postgresql-atlas.definitive-routing-eval.json
        evals/postgresql-atlas.definitive-skill-eval.json
        evals/definitive-skill-router.json
      ]
    },
    "scenario-proofs"=>{
      "commands"=>[
        ["ruby", "tools/generate-scenario-proofs.rb"]
      ],
      "patterns"=>[
        "artifacts/reference-system/results.json",
        "artifacts/reference-system/traces/**/*",
        "artifacts/reference-system/observations/**/*",
        "integrations/reference-system/manifest.json",
        "evidence/scenarios/index.json",
        "evidence/scenarios/behaviors/**/*.proof.json"
      ]
    },
    "scenario-closure-plan"=>{
      "commands"=>[
        ["ruby", "tools/generate-scenario-closure-plan.rb"]
      ],
      "paths"=>%w[
        evidence/scenarios/closure-plan.json
      ]
    },
    "provenance"=>{
      "commands"=>[
        ["ruby", "tools/generate-provenance.rb"]
      ],
      "paths"=>%w[
        provenance.yaml
      ]
    },
    "graph"=>{
      "commands"=>[
        ["ruby", "tools/generate-evidence-dependency-graph.rb"]
      ],
      "paths"=>%w[
        evidence/dependency-graph.json
      ]
    },
    "all-tracked"=>{
      "commands"=>[
        ["bash", "scripts/static-gates.sh"],
        ["bash", "evals/run.sh"],
        ["ruby", "tools/generate-scenario-proofs.rb"],
        ["ruby", "tools/generate-scenario-closure-plan.rb"],
        ["ruby", "tools/generate-provenance.rb"],
        ["ruby", "tools/generate-evidence-dependency-graph.rb"]
      ],
      "all_generated"=>true
    }
  }.freeze

  module_function

  def files(root, *patterns)
    patterns.flat_map { |pattern| Dir.glob(File.join(root, pattern)) }
      .select { |path| File.file?(path) }
      .map { |path| relative(root, path) }
      .uniq
      .sort
  end

  def relative(root, path)
    path.delete_prefix("#{root}/")
  end

  def ledger_output_path?(path)
    return false if [EvidenceDependencyGraph::LEDGER_PATH, EvidenceDependencyGraph::GRAPH_PATH, "evals/cases.json"].include?(path)
    return true if path == "provenance.yaml"
    return true if path.start_with?("artifacts/")
    return true if path.start_with?("evidence/artifacts/", "evidence/harnesses/", "evidence/scenarios/")
    return true if path.start_with?("evidence/") && path.match?(%r{\Aevidence/[^/]+\.evidence\.(json|ya?ml)\z})

    path.start_with?("evals/") && path.end_with?(".json")
  end

  def generated_output_paths(root)
    (files(
      root,
      "evidence/*.evidence.{json,yaml,yml}",
      "evidence/artifacts/**/*",
      "evidence/harnesses/*.manifest",
      "evidence/scenarios/**/*",
      "artifacts/**/*",
      "evals/**/*.json",
      "provenance.yaml"
    ).select { |path| ledger_output_path?(path) } + [EvidenceDependencyGraph::GRAPH_PATH])
      .uniq
      .sort
  end

  def digest(path)
    "sha256:#{Digest::SHA256.file(path).hexdigest}"
  end

  def copy_repo(root, destination)
    Dir.children(root).each do |entry|
      next if EXCLUDED_ROOT_ENTRIES.include?(entry)

      FileUtils.cp_r(File.join(root, entry), destination, preserve: true)
    end
  end

  def profile(name)
    PROFILES.fetch(name)
  end

  def temporary_root
    root = ENV["RUNNER_TEMP"] || ENV["TMPDIR"] || Dir.tmpdir
    FileUtils.mkdir_p(root)
    root
  end

  def with_tempdir(prefix, parent = temporary_root, &block)
    Dir.mktmpdir(prefix, parent, &block)
  end

  def run_generators!(root, commands)
    env = {"TMPDIR"=>root}
    commands.each do |command|
      stdout, stderr, status = Open3.capture3(env, *command, chdir: root)
      next if status.success?

      details = [stdout, stderr].reject(&:empty?).join
      raise "Generated output freshness failed while running `#{command.join(' ')}`\n#{details}"
    end
  end

  def profile_paths(root, name)
    config = profile(name)
    return generated_output_paths(root) if config["all_generated"]

    explicit = Array(config["paths"])
    from_patterns = files(root, *Array(config["patterns"]))
    (explicit + from_patterns).uniq.sort
  end

  def compare_roots!(expected_root, actual_root, name = "all-tracked")
    expected_paths = profile_paths(expected_root, name)
    actual_paths = profile_paths(actual_root, name)
    missing = expected_paths - actual_paths
    extra = actual_paths - expected_paths
    raise "Generated output set drift: missing #{missing.first}" unless missing.empty?
    raise "Generated output set drift: unexpected #{extra.first}" unless extra.empty?

    expected_paths.each do |relative_path|
      expected = File.join(expected_root, relative_path)
      actual = File.join(actual_root, relative_path)
      next if File.file?(actual) && digest(expected) == digest(actual) && File.size(expected) == File.size(actual)

      raise <<~MESSAGE
        Generated output drift: #{relative_path}
        expected_digest=#{digest(expected)}
        actual_digest=#{File.file?(actual) ? digest(actual) : "missing"}
        #{diff_excerpt(expected, actual)}
      MESSAGE
    end
    expected_paths.length
  end

  def diff_excerpt(expected, actual)
    return "actual file is missing" unless File.file?(actual)

    stdout, = Open3.capture2("diff", "-u", expected, actual)
    lines = stdout.lines.first(80)
    return "byte mismatch with no textual diff excerpt available" if lines.empty?

    lines.join
  rescue StandardError => e
    "byte mismatch and diff extraction failed: #{e.message}"
  end

  def verify!(name = "all-tracked", root = ROOT)
    with_tempdir("pgra-generated-freshness.") do |tmp|
      copy_repo(root, tmp)
      run_generators!(tmp, profile(name).fetch("commands"))
      compare_roots!(root, tmp, name)
    end
  end
end
