#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/postgresql-skill-routing"

root = File.expand_path("..", __dir__)
artifact = JSON.parse(File.read(File.join(root, "evals/postgresql-atlas.definitive-routing-eval.json")))
core_eval = JSON.parse(File.read(File.join(root, "evals/postgresql-atlas.definitive-skill-eval.json")))
ctx = PostgreSQLSkillRouting.context(root)
expected_matrix = PostgreSQLSkillRouting.matrix_requests(ctx).map do |request|
  PostgreSQLSkillRouting.evaluate_plan(root, PostgreSQLSkillRouting.plan(root, request, ctx), request, ctx)
end
abort "8 Outcome × 14 Surface matrixが完全ではありません" unless artifact.fetch("matrix") == expected_matrix && expected_matrix.length == 112
abort "Outcome/Surface coverageが重複または欠落しています" unless expected_matrix.map { |item| [item.fetch("outcome"), item.fetch("surface")] }.uniq.length == 112
abort "Matrix contract assertionが不合格です" unless expected_matrix.all? { |item| item.fetch("contract_result") == "pass" && item.fetch("contract_assertions").values.all? }
abort "Matrix passをcompletionへ転用しています" unless artifact.dig("summary", "matrix_pass_counts_as_completion") == false && artifact.fetch("completion_limits").any? { |line| line.include?("完成判定") }
abort "共有runtime bindingがquery plan/WAL/Versionへ接続されていません" unless expected_matrix.all? do |item|
  binding = item.fetch("runtime_integration_binding")
  binding.fetch("server_version") == "18.6" && binding.fetch("query_plan_pointer") == "/query_plan" && binding.fetch("wal_pointer") == "/wal_bytes_delta" && binding.fetch("claim_scope") == "shared-integration-slice-not-target-completion-proof"
end
abort "Target/Variant/Authority bindingが不足しています" unless expected_matrix.all? do |item|
  item.fetch("target_id").length > 3 && item.fetch("variant_bindings").length >= 2 && item.fetch("authority_bindings").any? && item.fetch("variant_bindings").all? { |binding| File.file?(File.join(root, binding.fetch("path"))) }
end
ledger = artifact.fetch("target_state_ledger")
expected_targets = ctx.fetch("targets")
abort "全Target stateが機械記録されていません" unless ledger.length == expected_targets.length && ledger.map { |item| [item.fetch("id"), item.fetch("state")] } == expected_targets.map { |item| [item.fetch("id"), item.fetch("state")] }
abort "Routing gapが隠されています" unless artifact.dig("summary", "routing_gaps") == expected_matrix.count { |item| item.fetch("coverage_disposition") != "bounded-evidence-route" }

boundaries = artifact.fetch("boundary_cases").to_h { |item| [item.fetch("id"), item] }
%w[boundary.ambiguous boundary.unknown boundary.unauthorized-build boundary.human-authority boundary.stale-relock].each do |id|
  abort "Boundary caseが不合格です: #{id}" unless boundaries.fetch(id).fetch("contract_result") == "pass" && boundaries.fetch(id).fetch("status") == "blocked"
end
forward = artifact.fetch("independent_agent_forward_eval")
abort "Forward Evalのcompletion creditが不正です" unless forward.fetch("completion_credit") == false
abort "Forward Eval resultが不正です" unless %w[pass fail inconclusive].include?(forward.fetch("result"))
if forward.fetch("result") == "pass"
  abort "独立Agent reviewer provenanceが不足しています" unless forward.fetch("reviewer").start_with?("independent-codex-agent:") && forward.fetch("prompt_digest").match?(/\Asha256:[a-f0-9]{64}\z/) && forward.fetch("evaluated_commit").include?("dirty-reviewed")
  abort "独立Agent Forward caseが不足しています" unless forward.fetch("cases").length >= 5 && forward.fetch("cases").all? { |item| item.fetch("result") == "pass" }
  forward.fetch("cases").each do |record|
    observed = PostgreSQLSkillRouting.plan(root, record.fetch("input").merge("id"=>record.fetch("id")), ctx)
    abort "Forward caseの実行観測がdriftしています: #{record.fetch('id')}" unless observed.fetch("status") == record.fetch("observed_status") && observed.fetch("blocked_reasons") == record.fetch("observed_blocked_reasons") && observed.fetch("target_id") == record.fetch("target_id")
  end
  abort "Forward Evalが初回実行不具合を記録していません" unless forward.fetch("findings").any? { |item| item.fetch("id") == "initial-wrapper-defect-recovered" }
end

expected_core_cases = expected_matrix.length + boundaries.length + 1
abort "Core Definitive Skill Evalが詳細記録と一致しません" unless core_eval.fetch("cases").length == expected_core_cases && core_eval.fetch("cases").count { |item| item.fetch("result") == "pass" } >= expected_matrix.length + boundaries.length
abort "Core EvalがOutcome/Surface全件を覆っていません" unless core_eval.fetch("cases").flat_map { |item| item.fetch("outcome_ids") }.uniq.sort == ctx.dig("mastery", "outcomes").map { |item| item.fetch("id") }.sort && core_eval.fetch("cases").flat_map { |item| item.fetch("surface_ids") }.uniq.sort == ctx.dig("mastery", "surfaces").map { |item| item.fetch("id") }.sort
puts "Verified Definitive Skill Eval: matrix=112 routing_gaps=#{artifact.dig('summary', 'routing_gaps')} targets=#{ledger.length} boundaries=5/5 forward=#{forward.fetch('result')} completion_credit=false"
