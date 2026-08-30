# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module SecurityFailureDiagnostics
  class Error < StandardError; end
  class ScenarioOracleFailure < StandardError
    attr_reader :failed_row, :target, :oracle_error, :actual_result, :oracle_predicates

    def initialize(failed_row:, target:, oracle_error:, actual_result: {}, oracle_predicates: {})
      super(oracle_error)
      @failed_row = failed_row
      @target = target
      @oracle_error = oracle_error
      @actual_result = actual_result
      @oracle_predicates = oracle_predicates
    end
  end

  SECRET_PATTERNS = [
    /BEGIN [A-Z ]*PRIVATE KEY/,
    /\bAKIA[0-9A-Z]{16}\b/,
    /postgres(ql)?:\/\/[^[:space:]]+/i,
    /\bpassword\s*=/i
  ].freeze
  ABSOLUTE_PATH_PATTERNS = [
    %r{/(Users|private|tmp|var/folders)/},
    %r{\A[A-Za-z]:\\}
  ].freeze
  RUN_ID_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/.freeze

  module_function

  def sha256_bytes(bytes)
    "sha256:#{Digest::SHA256.hexdigest(bytes)}"
  end

  def canonical_artifact_snapshot(root, report_relative: "artifacts/pattern-scenarios/results.json")
    report_path = File.join(root, report_relative)
    report = JSON.parse(File.read(report_path))
    files = [report_path] + report.fetch("tests").flat_map do |test|
      [
        File.join(root, test.dig("trace", "path")),
        File.join(root, test.dig("screenshot", "path"))
      ]
    end
    artifacts = files.sort.map do |path|
      {
        "path"=>path.delete_prefix("#{root}/"),
        "digest"=>"sha256:#{Digest::SHA256.file(path).hexdigest}",
        "bytes"=>File.size(path)
      }
    end
    {
      "count"=>artifacts.length,
      "collection_digest"=>sha256_bytes(JSON.generate(artifacts)),
      "artifacts"=>artifacts
    }
  end

  def performance_execution_failure_document(run_id:, recorded_at:, actual_result:, predicates:, source_digest:, harness_digest:, canonical_pre:, canonical_post:)
    {
      "schema_version"=>1,
      "kind"=>"postgresql-scenario-runtime-failure-diagnostic",
      "run_id"=>run_id,
      "recorded_at"=>recorded_at,
      "failed_row"=>"closure.definitive-domain.performance.execution.security",
      "target"=>"performance.execution",
      "oracle_error"=>"performance.execution security Oracle failed",
      "command"=>"ruby tools/run-scenario-security-001.rb",
      "profile"=>"real-postgresql-18.6-container",
      "attempt_policy"=>{"workers"=>1, "retries"=>0, "first_attempt_only"=>true},
      "bindings"=>{"source_digest"=>source_digest, "harness_digest"=>harness_digest},
      "actual_result"=>actual_result,
      "oracle_predicates"=>predicates,
      "plan_nodes"=>recursive_plan_nodes(actual_result.fetch("plan")),
      "canonical_artifacts"=>{
        "pre"=>canonical_pre,
        "post"=>canonical_post,
        "unchanged"=>canonical_pre.fetch("collection_digest") == canonical_post.fetch("collection_digest")
      }
    }
  end

  def generic_failure_document(run_id:, recorded_at:, failure:, source_digest:, harness_digest:, canonical_pre:, canonical_post:)
    {
      "schema_version"=>1,
      "kind"=>"postgresql-scenario-runtime-failure-diagnostic",
      "run_id"=>run_id,
      "recorded_at"=>recorded_at,
      "failed_row"=>failure.failed_row,
      "target"=>failure.target,
      "oracle_error"=>failure.oracle_error,
      "command"=>"ruby tools/run-scenario-security-001.rb",
      "profile"=>"real-postgresql-18.6-container",
      "attempt_policy"=>{"workers"=>1, "retries"=>0, "first_attempt_only"=>true},
      "bindings"=>{"source_digest"=>source_digest, "harness_digest"=>harness_digest},
      "actual_result"=>failure.actual_result,
      "oracle_predicates"=>failure.oracle_predicates,
      "plan_nodes"=>recursive_plan_nodes(failure.actual_result["plan"]),
      "canonical_artifacts"=>{
        "pre"=>canonical_pre,
        "post"=>canonical_post,
        "unchanged"=>canonical_pre.fetch("collection_digest") == canonical_post.fetch("collection_digest")
      }
    }
  end

  def recursive_plan_nodes(plan_document)
    return [] unless plan_document.is_a?(Array) && plan_document.first.is_a?(Hash) && plan_document.first["Plan"].is_a?(Hash)

    flatten_plan(plan_document.first["Plan"])
  end

  def flatten_plan(node)
    summary = {
      "node_type"=>node["Node Type"],
      "relation_name"=>node["Relation Name"],
      "index_name"=>node["Index Name"],
      "actual_rows"=>node["Actual Rows"],
      "actual_loops"=>node["Actual Loops"],
      "shared_hit_blocks"=>node["Shared Hit Blocks"],
      "shared_read_blocks"=>node["Shared Read Blocks"]
    }.compact
    [summary] + Array(node["Plans"]).flat_map { |child| child.is_a?(Hash) ? flatten_plan(child) : [] }
  end

  def write_append_only!(output_root, document)
    validate_document!(document)
    FileUtils.mkdir_p(output_root)
    filename = "#{document.fetch("run_id")}__#{document.fetch("failed_row").gsub(/[^a-zA-Z0-9._-]+/, "_")}.json"
    absolute = File.join(output_root, filename)
    raise Error, "failure diagnostic already exists: #{filename}" if File.exist?(absolute)

    tmp = "#{absolute}.tmp-#{Process.pid}"
    File.write(tmp, JSON.pretty_generate(document) + "\n")
    File.rename(tmp, absolute)
    absolute
  ensure
    FileUtils.rm_f(tmp) if defined?(tmp) && tmp && File.exist?(tmp)
  end

  def validate_document!(document)
    required = %w[schema_version kind run_id recorded_at failed_row target oracle_error command profile attempt_policy bindings actual_result oracle_predicates plan_nodes canonical_artifacts]
    missing = required.reject { |key| document.key?(key) }
    raise Error, "failure diagnostic schema is invalid: missing #{missing.join(', ')}" unless missing.empty?
    raise Error, "failure diagnostic kind is invalid" unless document.fetch("kind") == "postgresql-scenario-runtime-failure-diagnostic"
    run_id = document.fetch("run_id")
    raise Error, "failure diagnostic run_id is invalid" unless run_id.match?(RUN_ID_PATTERN) && !run_id.include?("..")
    raise Error, "failure diagnostic append-only state is invalid" unless document.dig("canonical_artifacts", "pre", "count") == 33 && document.dig("canonical_artifacts", "post", "count") == 33
    scan_forbidden_content!(document)
  end

  def record_failure(output_root:, document:, original_error:, io: $stderr)
    write_append_only!(output_root, document)
  rescue Error => diagnostic_error
    io.puts("failure diagnostic write failed: #{diagnostic_error.message}; preserving original failure: #{original_error.class}: #{original_error.message}")
    nil
  end

  def scan_forbidden_content!(value)
    case value
    when Hash
      value.each_value { |child| scan_forbidden_content!(child) }
    when Array
      value.each { |child| scan_forbidden_content!(child) }
    when String
      raise Error, "failure diagnostic contains absolute path" if ABSOLUTE_PATH_PATTERNS.any? { |pattern| value.match?(pattern) }
      raise Error, "failure diagnostic contains secret-like material" if SECRET_PATTERNS.any? { |pattern| value.match?(pattern) }
    end
  end
end
