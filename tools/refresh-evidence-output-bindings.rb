#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require_relative "lib/evidence_dependency_graph"
require_relative "lib/security_scenario_tranche"

ALLOWED_INPUT_DRIFT = %w[
  harness.scenario-skill-reporting
  harness.evidence-dependency-control-plane
].freeze
RESULTS_PATH = "artifacts/pattern-scenarios/results.json"
SCENARIO_MATRIX_PATH = "verification.matrix.yaml"
SCENARIO_RUNTIME_PATH = "tools/run-scenario-security-001.rb"

def digest_file(path)
  "sha256:#{Digest::SHA256.file(EvidenceDependencyGraph.absolute(path)).hexdigest}"
end

def verify_runtime_backing!
  results = JSON.parse(File.read(EvidenceDependencyGraph.absolute(RESULTS_PATH)))
  plan = JSON.parse(File.read(SecurityScenarioTranche::PLAN_PATH))
  completed_rows = SecurityScenarioTranche.verify_completed_suite!(plan)
  expected_patterns = SecurityScenarioTranche::COMPLETED_PATTERN_IDS
  actual_patterns = results.fetch("tests").map { |test| test.fetch("pattern_id") }
  raise "Scenario runtime published pattern setがclosure plan completed_rowsと一致しません" unless actual_patterns == expected_patterns

  expected_tests = completed_rows.map do |row|
    {
      "pattern_id"=>row.fetch("pattern_id"),
      "scenario"=>row.fetch("scenario"),
      "variant_ids"=>Array(row.fetch("variant_ids")).sort
    }
  end
  actual_tests = results.fetch("tests").map do |test|
    {
      "pattern_id"=>test.fetch("pattern_id"),
      "scenario"=>test.fetch("scenario"),
      "variant_ids"=>[test.fetch("variant_id")].sort
    }
  end
  raise "Scenario runtime test bindingsがclosure plan completed_rowsと一致しません" unless actual_tests == expected_tests

  exact_row_count = completed_rows.length
  counts = results.fetch("counts")
  raise "Scenario runtime publishが成功状態ではありません" unless counts == {
    "rows"=>exact_row_count, "variants"=>exact_row_count, "total"=>exact_row_count, "passed"=>exact_row_count, "failed"=>0, "flaky"=>0, "skipped"=>0
  }
  raise "Scenario runtime report test cardinalityがclosure plan completed_rowsと一致しません" unless results.fetch("tests").length == exact_row_count
  raise "Scenario closure summary completed_dedicated_rowsがruntime rowsと一致しません" unless plan.dig("summary", "completed_dedicated_rows") == exact_row_count
  raise "Scenario runtime report contains non-first-attempt results" unless results.fetch("tests").all? { |test| test.fetch("attempts") == 1 && test.fetch("final_status") == "passed" && test["error"].nil? }
  raise "Scenario runtime source digestがcurrent matrixへ結ばれていません" unless results.fetch("source_digest") == digest_file(SCENARIO_MATRIX_PATH)
  raise "Scenario runtime harness digest formatが不正です" unless results.fetch("harness_digest").to_s.match?(/\Asha256:[0-9a-f]{64}\z/)
end

def verify_allowed_input_drift!(ledger)
  current = EvidenceDependencyGraph.current_input_bindings
  bound = ledger.fetch("input_bindings").to_h { |item| [item.fetch("input_id"), item.fetch("digest")] }
  mismatches = current.select { |binding| bound[binding.fetch("id")] != binding.fetch("digest") }
  unexpected = mismatches.reject { |binding| ALLOWED_INPUT_DRIFT.include?(binding.fetch("id")) }
  raise "Full rerunなしで再結束できない入力driftがあります: #{unexpected.first.fetch('id')}" unless unexpected.empty?
  verify_runtime_backing! if mismatches.any? { |binding| binding.fetch("id") == "harness.scenario-skill-reporting" }
  current
end

ledger_path = EvidenceDependencyGraph.absolute(EvidenceDependencyGraph::LEDGER_PATH)
ledger = JSON.parse(File.read(ledger_path))
current_inputs = verify_allowed_input_drift!(ledger)
bindings = EvidenceDependencyGraph.current_output_bindings(include_graph: false)
ledger["input_bindings"] = current_inputs.map { |binding| {"input_id"=>binding.fetch("id"), "digest"=>binding.fetch("digest")} }
ledger["output_bindings"] = bindings
ledger["output_binding_phase"] = "tracked-generators-bound"
ledger["refresh_context"] = {
  "kind"=>"published-output-binding-refresh",
  "runtime_source"=>"current-published-outputs",
  "allowed_input_drift"=>ALLOWED_INPUT_DRIFT,
  "scenario_runtime_results"=>RESULTS_PATH
}

bytes = JSON.pretty_generate(ledger) + "\n"
temporary = "#{ledger_path}.staging-#{Process.pid}"
begin
  File.binwrite(temporary, bytes)
  File.rename(temporary, ledger_path)
  puts "Refreshed full-run output bindings from current published outputs: #{bindings.length} bindings"
ensure
  File.delete(temporary) if defined?(temporary) && File.exist?(temporary)
end
