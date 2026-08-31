#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_json_output"

MARKER = "ATLAS_SECURITY_PASS:query.security"
FAILED_ROW = "closure.definitive-domain.query.security.security"
TARGET = "query.security"
COMMAND = ["docker", "exec", "-i", "pg-atlas-security-test", "psql", "-XAt", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas"].freeze

def assert_parse_failure(stdout:, stderr:, reason:)
  begin
    SecurityJsonOutput.parse_single_json_object!(
      stdout: stdout,
      stderr: stderr,
      marker: MARKER,
      command: COMMAND,
      exit_status: 0,
      failed_row: FAILED_ROW,
      target: TARGET,
      phase: "json-parse"
    )
    abort "#{reason} regression was accepted"
  rescue SecurityFailureDiagnostics::ScenarioOracleFailure => error
    abort "failed_row drifted for #{reason}" unless error.failed_row == FAILED_ROW
    abort "target drifted for #{reason}" unless error.target == TARGET
    abort "oracle_error drifted for #{reason}" unless error.oracle_error.include?(reason)
    actual = error.actual_result
    abort "phase drifted for #{reason}" unless actual.fetch("phase") == "json-parse"
    abort "command binding drifted for #{reason}" unless actual.dig("command_failure", "command") == COMMAND.join(" ")
    abort "exit status drifted for #{reason}" unless actual.dig("command_failure", "exit_status") == 0
    abort "stdout binding missing for #{reason}" unless actual.dig("command_failure", "stdout").is_a?(String)
    abort "stderr binding missing for #{reason}" unless actual.dig("command_failure", "stderr").is_a?(String)
    abort "candidate lines binding missing for #{reason}" unless actual.key?("json_candidate_lines")
    abort "marker binding missing for #{reason}" unless actual.key?("marker_present")
  end
end

parsed = SecurityJsonOutput.parse_single_json_object!(
  stdout: %({\"server_version\":\"18.6\",\"visible_rows\":1,\"tenant_escape_denied\":true,\"sqlstate\":\"42501\",\"password_encryption\":\"scram-sha-256\",\"scram_verifier\":true,\"host_scram_rule\":true,\"fixed_search_path\":true,\"security_rejected\":true,\"oracle_marker\":\"#{MARKER}\",\"verdict\":\"pass\"}\n),
  stderr: "",
  marker: MARKER,
  command: COMMAND,
  exit_status: 0,
  failed_row: FAILED_ROW,
  target: TARGET,
  phase: "json-parse"
)
abort "single JSON object pass shape rejected" unless parsed.is_a?(Hash) && parsed.fetch("oracle_marker") == MARKER

assert_parse_failure(stdout: "", stderr: "", reason: "missing-json")
assert_parse_failure(stdout: "NOTICE: #{MARKER}\n", stderr: "", reason: "marker-only")
assert_parse_failure(stdout: "[]\n", stderr: "", reason: "non-object-json")
assert_parse_failure(stdout: "{\"a\":1}\n{\"b\":2}\n", stderr: "", reason: "multiple-json")
assert_parse_failure(stdout: "{\"a\":1\n", stderr: "", reason: "truncated-json")

puts "query.security JSON contractを検証しました: missing/non-object/marker-only/multiple/truncated JSON are rejected and exact row-target diagnostics are preserved"
