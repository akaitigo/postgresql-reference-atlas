#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/postgresql-skill-routing"

root = File.expand_path("..", __dir__)
ctx = PostgreSQLSkillRouting.context(root)
matrix = PostgreSQLSkillRouting.matrix_requests(ctx).map do |request|
  PostgreSQLSkillRouting.evaluate_plan(root, PostgreSQLSkillRouting.plan(root, request, ctx), request, ctx)
end
boundaries = [
  {"id"=>"boundary.ambiguous", "outcome"=>"choose", "surface"=>"decision-comparison", "query"=>"WALかIndexか不明なので両方変更", "expected_reason"=>"ambiguous-or-unknown-query"},
  {"id"=>"boundary.unknown", "outcome"=>"understand", "surface"=>"orientation-scope", "query"=>"quantum hologram telepathy", "expected_reason"=>"ambiguous-or-unknown-query"},
  {"id"=>"boundary.unauthorized-build", "outcome"=>"build", "surface"=>"implementation-construction", "query"=>"SQL Constraintを構築", "expected_reason"=>"unauthorized-mutation"},
  {"id"=>"boundary.human-authority", "outcome"=>"delegate", "surface"=>"agent-skill", "query"=>"Authority anchorをAgentに分類委任", "authorized_change"=>true, "authority_semantic_decision"=>true, "expected_reason"=>"external-human-decision-required"},
  {"id"=>"boundary.stale-relock", "outcome"=>"evolve", "surface"=>"provenance-rights", "query"=>"stale Sourceをrelockして移行", "authorized_change"=>true, "stale_source_relock"=>true, "expected_reason"=>"stale-source-relock-explicit-procedure-required"}
].map do |request|
  plan = PostgreSQLSkillRouting.plan(root, request, ctx)
  plan.merge("contract_result"=>(plan.fetch("status") == "blocked" && plan.fetch("blocked_reasons").include?(request.fetch("expected_reason")) ? "pass" : "fail"), "expected_blocked_reason"=>request.fetch("expected_reason"))
end

forward_path = File.join(root, "evals/postgresql-atlas.forward-agent-eval.json")
forward = File.file?(forward_path) ? JSON.parse(File.read(forward_path)) : {
  "schema_version"=>1, "id"=>"postgresql-atlas.forward-agent-v1", "status"=>"pending-independent-agent",
  "reviewer"=>nil, "evaluated_commit"=>nil, "prompt_digest"=>nil, "result"=>"inconclusive", "findings"=>[],
  "completion_credit"=>false, "reason"=>"独立AgentによるForward Evalがまだ記録されていない。"
}
source_paths = {
  "mastery"=>"mastery.yaml", "coverage"=>"coverage.yaml", "router"=>".agents/skills/postgresql-atlas/scripts/route.sh",
  "planner"=>".agents/skills/postgresql-atlas/scripts/plan-request.rb", "evaluator"=>"tools/generate-definitive-skill-eval.rb",
  "routing_library"=>"tools/lib/postgresql-skill-routing.rb", "skill"=>".agents/skills/postgresql-atlas/SKILL.md",
  "legacy_eval"=>"evals/postgresql-router.skill-eval.json"
}
source_bindings = source_paths.to_h { |id, path| [id, PostgreSQLSkillRouting.binding(root, path)] }
target_states = ctx.fetch("targets").map do |target|
  target.slice("id", "target_set", "requirement", "state", "claim_ids", "evidence_ids").merge(
    "matrix_routes"=>matrix.count { |item| item.fetch("target_id") == target.fetch("id") })
end
routing_gaps = matrix.count { |item| item.fetch("coverage_disposition") != "bounded-evidence-route" }
matrix_failures = matrix.count { |item| item.fetch("contract_result") != "pass" }
boundary_failures = boundaries.count { |item| item.fetch("contract_result") != "pass" }
artifact = {
  "schema_version"=>1, "id"=>"postgresql-atlas.definitive-routing-v1", "atlas_id"=>"postgresql-reference-atlas",
  "generated_at"=>PostgreSQLSkillRouting::GENERATED_AT,
  "status"=>(routing_gaps.zero? && boundary_failures.zero? && forward.fetch("result") == "pass" ? "evaluated-not-completion-certificate" : "incomplete-routing-or-forward-eval"),
  "semantic_scope"=>"deterministic-skill-routing-contract-plus-independent-agent-forward-eval",
  "reference"=>{"repository"=>"frontend-behavior-atlas", "commit"=>"8a9e34a89a55cc53702032783c06ede7246a286f", "absolute_counts_transplanted"=>false},
  "source_bindings"=>source_bindings,
  "summary"=>{"outcomes"=>ctx.dig("mastery", "outcomes").length, "surfaces"=>ctx.dig("mastery", "surfaces").length,
               "matrix_cells"=>matrix.length, "contract_passed"=>matrix.length-matrix_failures, "contract_failed"=>matrix_failures,
               "bounded_evidence_routes"=>matrix.length-routing_gaps, "routing_gaps"=>routing_gaps,
               "boundary_cases"=>boundaries.length, "boundary_passed"=>boundaries.length-boundary_failures, "boundary_failed"=>boundary_failures,
               "targets"=>target_states.length, "covered_targets"=>target_states.count { |target| target.fetch("state") == "covered" },
               "partial_targets"=>target_states.count { |target| target.fetch("state") == "partial" }, "planned_targets"=>target_states.count { |target| target.fetch("state") == "planned" },
               "independent_agent_forward_eval"=>forward.fetch("result"), "matrix_pass_counts_as_completion"=>false},
  "completion_limits"=>[
    "Matrix contract passはTarget、Authority review、Depth、Subjectの完成判定を意味しない。",
    "partial/planned TargetまたはTarget-set交差なしのCellはrouting gapとして残す。",
    "共有Reference Systemのquery plan/WAL/runtime bindingはTarget専用Proofの代替ではない。",
    "人によるAuthority decisionとstale relockをAgent結果として扱わない。"
  ],
  "target_state_ledger"=>target_states, "matrix"=>matrix, "boundary_cases"=>boundaries,
  "independent_agent_forward_eval"=>forward
}
File.write(File.join(root, "evals/postgresql-atlas.definitive-routing-eval.json"), JSON.pretty_generate(artifact) + "\n")

core_cases = matrix.map do |item|
  {"id"=>item.fetch("id"), "result"=>item.fetch("contract_result"), "outcome_ids"=>[item.fetch("outcome")], "surface_ids"=>[item.fetch("surface")],
   "gap_behavior"=>item.fetch("coverage_disposition") != "bounded-evidence-route", "authorization_boundary"=>item.fetch("mutation_policy") != "read-only",
   "assertion"=>"#{item.fetch('id')}はTarget stateと証拠境界を保持してRouteし、Matrix成功を完成判定へ転用しない。"}
end
core_cases.concat(boundaries.map do |item|
  {"id"=>item.fetch("id"), "result"=>item.fetch("contract_result"), "outcome_ids"=>[item.fetch("outcome")], "surface_ids"=>[item.fetch("surface")],
   "gap_behavior"=>true, "authorization_boundary"=>true,
   "assertion"=>"#{item.fetch('id')}は変更・Human Authority・stale relock・曖昧Queryをfail-closedで停止する。"}
end)
core_cases << {"id"=>"forward.independent-agent", "result"=>forward.fetch("result"), "outcome_ids"=>["delegate"], "surface_ids"=>["agent-skill"],
               "gap_behavior"=>forward.fetch("result") != "pass", "authorization_boundary"=>true,
               "assertion"=>"独立Agent Forward Evalを機械記録し、未実施または不合格を完成判定から分離する。"}
core_eval = {"schema_version"=>2, "id"=>"skill.postgresql-definitive-audit", "atlas_id"=>"postgresql-reference-atlas", "atlas_release"=>"v1.0.0",
             "skill_id"=>"postgresql-atlas", "generated_at"=>PostgreSQLSkillRouting::GENERATED_AT, "cases"=>core_cases}
File.write(File.join(root, "evals/postgresql-atlas.definitive-skill-eval.json"), JSON.pretty_generate(core_eval) + "\n")
puts "Definitive Skill Eval: matrix=#{matrix.length} bounded_routes=#{matrix.length-routing_gaps} routing_gaps=#{routing_gaps} boundaries=#{boundaries.length-boundary_failures}/#{boundaries.length} forward=#{forward.fetch('result')}"
