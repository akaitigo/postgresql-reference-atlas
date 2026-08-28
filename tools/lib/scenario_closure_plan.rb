# frozen_string_literal: true

require "digest"
require "json"

module ScenarioClosurePlan
  ROOT = File.expand_path("../..", __dir__)
  GENERATED_AT = "2026-08-28T00:00:00+09:00"
  INDEX_PATH = "evidence/scenarios/index.json"
  REPORT_PATH = "artifacts/pattern-scenarios/results.json"
  PLAN_PATH = "evidence/scenarios/closure-plan.json"
  RISK_ORDER = %w[security refusal failure recovery migration operations boundary performance compatibility normal].freeze
  REQUIRED_CLOSURE = {
    "drive_pattern_scenario_and_every_variant"=>true,
    "first_attempt_only"=>true,
    "retries"=>0,
    "dedicated_runtime_identity"=>true,
    "dedicated_oracle"=>true,
    "separate_trace_per_variant"=>true,
    "required_trace_streams"=>%w[action network resource],
    "separate_screenshot_per_variant"=>true,
    "source_and_harness_digests"=>true,
    "forbidden_substitutions"=>%w[metadata-only capture-reuse integrated-trace-reuse mock-or-static-runtime]
  }.freeze

  module_function

  def absolute(relative)
    File.join(ROOT, relative)
  end

  def digest(relative)
    "sha256:#{Digest::SHA256.file(absolute(relative)).hexdigest}"
  end

  def load_json(relative)
    JSON.parse(File.read(absolute(relative)))
  end

  def completed_rows(report, rank)
    report.fetch("tests").group_by { |test| [test.fetch("pattern_id"), test.fetch("scenario")] }.map do |(pattern_id, scenario), tests|
      {
        "pattern_id"=>pattern_id,
        "scenario"=>scenario,
        "oracle_kinds"=>tests.map { |test| test.dig("oracle", "kind") || "missing" }.uniq,
        "variant_ids"=>tests.map { |test| test.fetch("variant_id") }.sort,
        "all_first_attempt_pass"=>tests.all? { |test| test.fetch("outcome") == "expected" && test.fetch("attempts") == 1 && test.fetch("final_status") == "passed" },
        "all_trace_streams"=>tests.all? { |test| %w[action network resource].all? { |stream| test.dig("trace", "#{stream}_stream") == true } }
      }
    end.sort_by { |row| [rank.fetch(row.fetch("scenario")), row.fetch("pattern_id")] }
  end

  def build
    index = load_json(INDEX_PATH)
    report = load_json(REPORT_PATH)
    rank = RISK_ORDER.each_with_index.to_h
    files = index.fetch("files").select { |file| file.fetch("status") == "pattern-specific-gap" }
      .sort_by { |file| [rank.fetch(file.fetch("scenario")), file.fetch("pattern_id")] }
    rows = files.map do |file|
      proof = load_json(file.fetch("path"))
      {
        "id"=>"closure.#{proof.fetch('pattern_id').tr('/', '.')}.#{proof.fetch('scenario')}",
        "pattern_id"=>proof.fetch("pattern_id"),
        "target_id"=>proof.fetch("target_id"),
        "scenario"=>proof.fetch("scenario"),
        "risk_rank"=>rank.fetch(proof.fetch("scenario")) + 1,
        "proof"=>{"path"=>file.fetch("path"), "digest"=>file.fetch("digest")},
        "variant_ids"=>proof.fetch("source_bindings").map { |binding| binding.fetch("variant_id") },
        "required_closure"=>REQUIRED_CLOSURE,
        "gaps"=>proof.fetch("gaps")
      }
    end
    tranches = RISK_ORDER.flat_map do |scenario|
      rows.select { |row| row.fetch("scenario") == scenario }.each_slice(4).with_index(1).map do |selected, sequence|
        {
          "id"=>format("%s-%03d", scenario, sequence),
          "risk_rank"=>rank.fetch(scenario) + 1,
          "scenario"=>scenario,
          "status"=>"planned",
          "row_ids"=>selected.map { |row| row.fetch("id") },
          "pattern_rows"=>selected.length,
          "variant_runs"=>selected.sum { |row| row.fetch("variant_ids").length },
          "commit_policy"=>"one-reviewed-tranche-with-non-regression-runtime-identity-and-oracle-validation"
        }
      end
    end
    completed = completed_rows(report, rank)
    by_scenario = RISK_ORDER.to_h { |scenario| [scenario, rows.count { |row| row.fetch("scenario") == scenario }] }
    forward = load_json("evals/postgresql-atlas.forward-agent-eval.json")
    {
      "schema_version"=>1,
      "id"=>"postgresql-scenario-closure-plan-v1",
      "generated_at"=>GENERATED_AT,
      "status"=>tranches.empty? ? "complete" : "incomplete",
      "scope"=>"current-domain-postgresql-behavior-scenario-gaps-not-authority-atomic",
      "policy"=>{
        "risk_order"=>RISK_ORDER,
        "maximum_pattern_rows_per_tranche"=>4,
        "monotonic_addition"=>true,
        "mass_closure_forbidden"=>true
      },
      "source_digests"=>{INDEX_PATH=>digest(INDEX_PATH), REPORT_PATH=>digest(REPORT_PATH)},
      "baseline"=>{
        "inherited_gap_rows_at_bc41912f"=>290,
        "matrix_rows"=>index.dig("summary", "rows"),
        "patterns"=>index.dig("summary", "patterns"),
        "scenarios"=>index.dig("summary", "scenarios")
      },
      "summary"=>{
        "completed_dedicated_rows"=>completed.length,
        "remaining_rows"=>rows.length,
        "planned_tranches"=>tranches.length,
        "by_scenario"=>by_scenario
      },
      "independent_incomplete"=>{
        "authority_atomic_rows"=>index.dig("summary", "authority_atomic_rows"),
        "external_profiles"=>%w[multi-node-ha cross-version-upgrade managed-service-boundary corruption-recovery],
        "agent_forward_eval"=>"#{forward.fetch('result')}-without-scenario-closure-credit"
      },
      "completed_rows"=>completed,
      "next_tranche"=>tranches.first,
      "tranches"=>tranches,
      "rows"=>rows
    }
  end
end
