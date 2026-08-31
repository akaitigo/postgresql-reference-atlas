#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "../tools/lib/security_failure_diagnostics"
require_relative "../tools/lib/security_scenario_oracles"

ROOT = File.expand_path("..", __dir__)
FIXTURE_PATH = File.join(ROOT, "tests/fixtures/security-performance-execution-observed-seq-scan.json")

def build_canonical_snapshot_root
  Dir.mktmpdir("pg-security-diagnostics") do |dir|
    artifacts_root = File.join(dir, "artifacts/pattern-scenarios")
    trace_root = File.join(artifacts_root, "traces")
    observation_root = File.join(artifacts_root, "observations")
    FileUtils.mkdir_p(trace_root)
    FileUtils.mkdir_p(observation_root)

    tests = 20.times.map do |index|
      trace_name = format("row-%02d.trace.json", index + 1)
      observation_name = format("row-%02d.observable.json", index + 1)
      File.write(File.join(trace_root, trace_name), JSON.pretty_generate({"id"=>"trace-#{index + 1}"}) + "\n")
      File.write(File.join(observation_root, observation_name), JSON.pretty_generate({"id"=>"observation-#{index + 1}"}) + "\n")
      {
        "trace"=>{"path"=>"artifacts/pattern-scenarios/traces/#{trace_name}"},
        "screenshot"=>{"path"=>"artifacts/pattern-scenarios/observations/#{observation_name}"}
      }
    end

    File.write(
      File.join(artifacts_root, "results.json"),
      JSON.pretty_generate({
        "status"=>"passed",
        "counts"=>{"rows"=>16, "passed"=>16},
        "tests"=>tests
      }) + "\n"
    )

    yield dir
  end
end

def assert(condition, message)
  abort message unless condition
end

def build_failure_from_fixture(fixture:, actual_result:, predicates:)
  captured = fixture.fetch("captured_from")
  SecurityFailureDiagnostics::ScenarioOracleFailure.new(
    failed_row: captured.fetch("failed_row"),
    target: captured.fetch("target"),
    oracle_error: captured.fetch("oracle_error"),
    actual_result: actual_result,
    oracle_predicates: predicates
  )
end

fixture = JSON.parse(File.read(FIXTURE_PATH))
actual_result = fixture.fetch("actual_result")
captured_from = fixture.fetch("captured_from")
predicates = SecurityScenarioOracles.performance_execution_predicates(actual_result, marker: actual_result.fetch("oracle_marker"))

required_predicates = %w[
  result_verdict_pass
  server_version_exact
  fixture_rows_exact
  visible_rows_exact
  security_rejected
  marker_exact
  index_bytes_positive
  heap_bytes_positive
  plan_document_array
  plan_exact_index_path
  plan_actual_rows_and_loops
  plan_buffers_observed
  plan_seq_scan_absent_on_exact_relation
]

assert((required_predicates - predicates.keys).empty?, "oracle predicate keys drifted")
assert(predicates["plan_exact_index_path"] == false, "observed seq scan unexpectedly reported exact index path")
assert(predicates["plan_seq_scan_absent_on_exact_relation"] == false, "observed seq scan unexpectedly hid exact relation scan")

top_level_duplicate_fixture = fixture.merge(
  "failed_row"=>"closure.definitive-domain.performance.index.security",
  "target"=>"performance.index",
  "oracle_error"=>"top-level duplicate must be ignored"
)
top_level_duplicate_failure = build_failure_from_fixture(
  fixture: top_level_duplicate_fixture,
  actual_result: actual_result,
  predicates: predicates
)
assert(top_level_duplicate_failure.failed_row == captured_from.fetch("failed_row"), "top-level duplicate incorrectly replaced captured_from.failed_row")
assert(top_level_duplicate_failure.target == captured_from.fetch("target"), "top-level duplicate incorrectly replaced captured_from.target")
assert(top_level_duplicate_failure.oracle_error == captured_from.fetch("oracle_error"), "top-level duplicate incorrectly replaced captured_from.oracle_error")

begin
  missing_failed_row_fixture = Marshal.load(Marshal.dump(fixture))
  missing_failed_row_fixture.fetch("captured_from").delete("failed_row")
  build_failure_from_fixture(fixture: missing_failed_row_fixture, actual_result: actual_result, predicates: predicates)
  abort "captured_from.failed_row missing key was accepted"
rescue KeyError
end

begin
  remapped_captured_from_fixture = Marshal.load(Marshal.dump(fixture))
  remapped_captured_from_fixture["captured_from_renamed"] = remapped_captured_from_fixture.delete("captured_from")
  build_failure_from_fixture(fixture: remapped_captured_from_fixture, actual_result: actual_result, predicates: predicates)
  abort "captured_from path rename was accepted"
rescue KeyError
end

build_canonical_snapshot_root do |dir|
  pre = SecurityFailureDiagnostics.canonical_artifact_snapshot(dir)
  post = SecurityFailureDiagnostics.canonical_artifact_snapshot(dir)
  document = SecurityFailureDiagnostics.generic_failure_document(
    run_id: "security-001-20260831T000000Z-12345",
    recorded_at: "2026-08-31T00:00:00Z",
    failure: build_failure_from_fixture(fixture: fixture, actual_result: actual_result, predicates: predicates),
    source_digest: "sha256:source-digest",
    harness_digest: "sha256:harness-digest",
    canonical_pre: pre,
    canonical_post: post
  )

  SecurityFailureDiagnostics.validate_document!(document)
  assert(document.dig("canonical_artifacts", "unchanged") == true, "canonical artifact retention drifted")
  assert(document.dig("attempt_policy", "workers") == 1, "workers contract drifted")
  assert(document.dig("attempt_policy", "retries") == 0, "retry contract drifted")
  assert(document.fetch("command") == captured_from.fetch("command"), "captured_from command mapping drifted")
  assert(document.fetch("attempt_policy") == captured_from.fetch("attempt_policy"), "captured_from attempt policy mapping drifted")
  assert(document.fetch("failed_row") == captured_from.fetch("failed_row"), "captured_from failed_row mapping drifted")
  assert(document.fetch("target") == captured_from.fetch("target"), "captured_from target mapping drifted")
  assert(document.fetch("oracle_error") == captured_from.fetch("oracle_error"), "captured_from oracle_error mapping drifted")
  assert(document.fetch("plan_nodes").any? { |node| node["node_type"] == "Seq Scan" && node["relation_name"] == "atlas_perf_execution_secure" }, "plan node flattening drifted")

  output_root = File.join(dir, "artifacts/pattern-scenario-failures")
  written_path = SecurityFailureDiagnostics.write_append_only!(output_root, document)
  written = JSON.parse(File.read(written_path))
  assert(written.fetch("failed_row") == captured_from.fetch("failed_row"), "written diagnostic row drifted")
  assert(written.fetch("oracle_predicates") == predicates, "written diagnostic predicate binding drifted")

  begin
    SecurityFailureDiagnostics.write_append_only!(output_root, document)
    abort "failure diagnostic overwrite was accepted"
  rescue SecurityFailureDiagnostics::Error => error
    assert(error.message.include?("already exists"), "overwrite rejection drifted")
  end

  begin
    SecurityFailureDiagnostics.validate_document!(document.reject { |key, _| key == "failed_row" })
    abort "missing required field was accepted"
  rescue SecurityFailureDiagnostics::Error => error
    assert(error.message.include?("schema is invalid"), "schema rejection drifted")
  end

  begin
    mutated = Marshal.load(Marshal.dump(document))
    mutated.dig("canonical_artifacts", "pre")["count"] = 39
    mutated.dig("canonical_artifacts", "pre")["artifacts"] = mutated.dig("canonical_artifacts", "pre", "artifacts").first(39)
    mutated.dig("canonical_artifacts", "post")["count"] = 39
    mutated.dig("canonical_artifacts", "post")["artifacts"] = mutated.dig("canonical_artifacts", "post", "artifacts").first(39)
    SecurityFailureDiagnostics.validate_document!(mutated)
    abort "canonical artifact floor shrink was accepted"
  rescue SecurityFailureDiagnostics::Error => error
    assert(error.message.include?("append-only state"), "canonical artifact floor rejection drifted")
  end

  begin
    mutated = Marshal.load(Marshal.dump(document))
    mutated["actual_result"]["leak"] = "/Users/example/private.txt"
    SecurityFailureDiagnostics.validate_document!(mutated)
    abort "absolute path leak was accepted"
  rescue SecurityFailureDiagnostics::Error => error
    assert(error.message.include?("absolute path"), "absolute path rejection drifted")
  end

  begin
    mutated = Marshal.load(Marshal.dump(document))
    mutated["actual_result"]["secret"] = ["BEGIN", "OPENSSH", "PRIVATE", "KEY"].join(" ")
    SecurityFailureDiagnostics.validate_document!(mutated)
    abort "secret-like content was accepted"
  rescue SecurityFailureDiagnostics::Error => error
    assert(error.message.include?("secret-like"), "secret rejection drifted")
  end

  begin
    mutated = Marshal.load(Marshal.dump(document))
    mutated["run_id"] = "../escape"
    SecurityFailureDiagnostics.validate_document!(mutated)
    abort "run_id traversal was accepted"
  rescue SecurityFailureDiagnostics::Error => error
    assert(error.message.include?("run_id is invalid"), "run_id validation drifted")
  end

  begin
    mutated = Marshal.load(Marshal.dump(document))
    mutated["run_id"] = "/tmp/escape"
    SecurityFailureDiagnostics.validate_document!(mutated)
    abort "absolute run_id was accepted"
  rescue SecurityFailureDiagnostics::Error => error
    assert(error.message.include?("run_id is invalid"), "absolute run_id rejection drifted")
  end

  begin
    mutated = Marshal.load(Marshal.dump(document))
    mutated["run_id"] = "segment/child"
    SecurityFailureDiagnostics.validate_document!(mutated)
    abort "run_id path separator was accepted"
  rescue SecurityFailureDiagnostics::Error => error
    assert(error.message.include?("run_id is invalid"), "separator run_id rejection drifted")
  end

  io = StringIO.new
  broken_document = Marshal.load(Marshal.dump(document))
  broken_document["run_id"] = "../escape"
  original_error = build_failure_from_fixture(fixture: fixture, actual_result: actual_result, predicates: predicates)
  result = SecurityFailureDiagnostics.record_failure(
    output_root: output_root,
    document: broken_document,
    original_error: original_error,
    io: io
  )
  assert(result.nil?, "record_failure must not surface diagnostic validation failure")
  assert(io.string.include?("preserving original failure"), "record_failure did not preserve original failure context")

  begin
    raise original_error
  rescue SecurityFailureDiagnostics::ScenarioOracleFailure => error
    SecurityFailureDiagnostics.record_failure(
      output_root: output_root,
      document: broken_document,
      original_error: error,
      io: StringIO.new
    )
    assert(error.message == captured_from.fetch("oracle_error"), "primary Oracle failure was not preserved")
  end
end

puts "security failure diagnostics contractを検証しました: predicate capture, append-only write, schema/path/secret scans, and overwrite rejection are green"
