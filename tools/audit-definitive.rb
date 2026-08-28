#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

root = File.expand_path("..", __dir__)
manifest = YAML.safe_load(File.read(File.join(root, "definitive.yaml")), aliases: false)
inventory = YAML.safe_load(File.read(File.join(root, manifest.fetch("surface_inventory"))), aliases: false)
matrix = YAML.safe_load(File.read(File.join(root, manifest.fetch("verification_matrix"))), aliases: false)
coverage = YAML.safe_load(File.read(File.join(root, "coverage.yaml")), aliases: false)
skill_eval = JSON.parse(File.read(File.join(root, manifest.fetch("skill_eval"))) )
definitive_skill = JSON.parse(File.read(File.join(root, "evals/postgresql-atlas.definitive-routing-eval.json")))
scenario_proofs = JSON.parse(File.read(File.join(root, "evidence/scenarios/index.json")))
evidence_ids = Dir.glob(File.join(root, "evidence/*.evidence.yaml")).map { |path| YAML.safe_load(File.read(path), aliases: false).fetch("id") }

artifact_errors = inventory.fetch("authority_artifacts").map do |artifact|
  path = File.join(root, artifact.fetch("path"))
  actual = File.file?(path) ? "sha256:#{Digest::SHA256.file(path).hexdigest}" : nil
  "#{artifact.fetch("id")}: digest/path mismatch" unless actual == artifact.fetch("digest")
end.compact
items = inventory.fetch("items")
unclassified = items.reject { |item| %w[included not-applicable].include?(item.fetch("classification")) }
duplicate_items = items.group_by { |item| item.fetch("id") }.select { |_id, group| group.length > 1 }.keys
target_by_id = coverage.fetch("targets").to_h { |target| [target.fetch("id"), target] }
unknown_targets = items.map { |item| item.fetch("target_id") }.uniq.reject { |id| target_by_id.key?(id) }
target_mismatches = items.map do |item|
  "#{item.fetch("id")}: target_id != capability_id" unless item.fetch("target_id") == item.fetch("capability_id")
end.compact

rows_by_behavior = matrix.fetch("rows").group_by { |row| row.fetch("behavior_id") }
required_by_kind = {
  "concept"=>%w[normal boundary rejection], "capability"=>%w[normal boundary rejection], "construction"=>%w[normal boundary rejection failure recovery],
  "operation"=>%w[normal boundary rejection failure recovery operations], "failure"=>%w[normal boundary rejection failure recovery], "security"=>%w[normal boundary rejection security],
  "performance"=>%w[normal boundary rejection performance], "compatibility"=>%w[normal boundary rejection compatibility],
  "migration"=>%w[normal boundary rejection migration compatibility recovery], "deprecation"=>%w[normal boundary rejection migration compatibility], "skill"=>%w[normal boundary rejection]
}.freeze
target_gaps = target_by_id.values.map do |target|
  behavior_id = "definitive-domain.#{target.fetch("id")}"
  actual = rows_by_behavior.fetch(behavior_id, []).select { |row| row.fetch("applicability") == "required" }.map { |row| row.fetch("scenario") }.uniq
  missing = required_by_kind.fetch(target.fetch("kind")) - actual
  stale_evidence = rows_by_behavior.fetch(behavior_id, []).flat_map { |row| row.fetch("evidence_ids") }.uniq - evidence_ids
  next if target.fetch("state") == "covered" && missing.empty? && stale_evidence.empty?
  {"target_id"=>target.fetch("id"),"state"=>target.fetch("state"),"missing_scenarios"=>missing,"unknown_evidence_ids"=>stale_evidence}
end.compact

claims_by_id = Dir.glob(File.join(root, "**/*.claim.yaml")).to_h do |path|
  claim = YAML.safe_load(File.read(path), aliases: false)
  [claim.fetch("id"), claim]
end
items_by_target = items.group_by { |item| item.fetch("target_id") }
items_by_claim = items.group_by { |item| item.fetch("claim_ids").first }
behavior_claim_gaps = items.reject do |item|
  claim_ids = item.fetch("claim_ids")
  claim = claim_ids.length == 1 && claims_by_id[claim_ids.first]
  target = target_by_id[item.fetch("target_id")]
  claim && claim.fetch("status") == "accepted" && claim.fetch("capability_id") == item.fetch("capability_id") &&
    items_by_target.fetch(item.fetch("target_id")).length == 1 && items_by_claim.fetch(claim_ids.first).length == 1 &&
    target.fetch("requirement") == "required" && target.fetch("state") == "covered" && target.fetch("claim_ids") == claim_ids
end
scenarios = %w[normal boundary rejection failure recovery migration operations security performance compatibility]
surface_scenarios = {
  "failure-recovery"=>%w[failure recovery], "operations-observability"=>%w[operations],
  "security-privacy-safety"=>%w[security], "performance-capacity-cost"=>%w[performance],
  "compatibility-integration"=>%w[compatibility], "migration-evolution-deprecation"=>%w[migration]
}.freeze
required_scenario_rows = items.sum do |item|
  (%w[normal boundary rejection] + item.fetch("surface_ids").flat_map { |surface| surface_scenarios.fetch(surface, []) }).uniq.length
end
row_keys = matrix.fetch("rows").map { |row| "#{row.fetch("behavior_id")}:#{row.fetch("scenario")}" }.uniq
required_row_keys = items.flat_map do |item|
  required = (%w[normal boundary rejection] + item.fetch("surface_ids").flat_map { |surface| surface_scenarios.fetch(surface, []) }).uniq
  required.map { |scenario| "#{item.fetch("behavior_id")}:#{scenario}" }
end

capabilities = items.map { |item| item.fetch("target_id") }.uniq.sort
routed = JSON.parse(File.read(File.join(root, "evidence/artifacts/skill-router-eval.json"))).fetch("results").map { |result| result.fetch("capability") }.uniq
legacy_skill_target_gaps = capabilities.reject { |id| routed.include?(id) || %w[publication.provenance foundation.version-lock foundation.authority-lock].include?(id) }
skill_target_gaps = definitive_skill.fetch("target_state_ledger").select { |target| target.fetch("matrix_routes") == 0 }.map { |target| target.fetch("id") }
outcomes = skill_eval.fetch("cases").flat_map { |item| item.fetch("outcome_ids") }.uniq
surfaces = skill_eval.fetch("cases").flat_map { |item| item.fetch("surface_ids") }.uniq
required_outcomes = %w[understand choose build verify operate troubleshoot evolve delegate]
required_surfaces = %w[orientation-scope foundations-mechanics architecture-design implementation-construction testing-verification failure-recovery operations-observability security-privacy-safety performance-capacity-cost compatibility-integration migration-evolution-deprecation decision-comparison provenance-rights agent-skill]

structural_gaps = []
structural_gaps << "integrated-reference-system" if manifest.fetch("reference_systems").empty?
structural_gaps << "multi-method-comparisons" if manifest.fetch("comparisons").empty?
structural_gaps << "runbook-exercise-evidence" unless target_by_id.fetch("operations.runbook-exercises").fetch("state") == "covered"
structural_gaps << "current-definitive-certificate" unless File.file?(File.join(root, manifest.fetch("certificate")))

report = {
  "schema_version"=>2,"atlas_id"=>manifest.fetch("atlas_id"),"verdict"=>"pending",
  "historical_certificate"=>manifest.fetch("historical_certificates").first,
  "inventory"=>{"items"=>items.length,"authority_artifacts"=>inventory.fetch("authority_artifacts").length,"by_target"=>items.group_by { |item| item.fetch("target_id") }.transform_values(&:length).sort.to_h,"unclassified"=>unclassified.length,"duplicate_ids"=>duplicate_items,"unknown_targets"=>unknown_targets,"target_mismatches"=>target_mismatches,"artifact_errors"=>artifact_errors},
  "verification"=>{"rows"=>matrix.fetch("rows").length,"expected_classification_rows"=>items.length*scenarios.length,"missing_classification_rows"=>items.length*scenarios.length-row_keys.length,"required_scenario_rows"=>required_scenario_rows,"missing_required_scenario_rows"=>(required_row_keys-row_keys).length,"behaviors_without_dedicated_accepted_claim"=>behavior_claim_gaps.length,"targets"=>target_by_id.length,"target_gaps"=>target_gaps,"open_targets"=>target_gaps.length},
  "scenario_proofs"=>scenario_proofs.slice("status", "denominator", "denominator_scope", "summary", "by_scenario", "completion_limits"),
  "skill"=>{"core_cases"=>skill_eval.fetch("cases").length,"matrix_cells"=>definitive_skill.dig("summary", "matrix_cells"),"bounded_evidence_routes"=>definitive_skill.dig("summary", "bounded_evidence_routes"),"routing_gaps"=>definitive_skill.dig("summary", "routing_gaps"),"boundary_cases"=>definitive_skill.dig("summary", "boundary_cases"),"independent_agent_forward_eval"=>definitive_skill.dig("summary", "independent_agent_forward_eval"),"matrix_pass_counts_as_completion"=>definitive_skill.dig("summary", "matrix_pass_counts_as_completion"),"missing_outcomes"=>required_outcomes-outcomes,"missing_surfaces"=>required_surfaces-surfaces,"unrouted_targets"=>skill_target_gaps,"legacy_router_unrouted_targets"=>legacy_skill_target_gaps,"target_states"=>definitive_skill.fetch("target_state_ledger")},
  "structural_gaps"=>structural_gaps,
  "promotion_blocked"=>true
}
File.write(File.join(root, "evidence/definitive-audit-report.json"), JSON.pretty_generate(report) + "\n")
scenario_summary = scenario_proofs.fetch("summary")
scenario_contract_valid = scenario_summary.fetch("rows") == 290 && scenario_summary.fetch("pattern_specific_rows") == 0 && scenario_summary.fetch("pattern_specific_runtime_rows") == 0 && scenario_summary.fetch("pattern_specific_gaps") == 290 && scenario_summary.fetch("integrated_trace_rows") == 290 && scenario_summary.fetch("authority_atomic_rows") == 0 && scenario_summary.fetch("completion_eligible_rows") == 0
abort "Definitive InventoryまたはScenario Proofに構造違反があります" unless artifact_errors.empty? && unclassified.empty? && duplicate_items.empty? && unknown_targets.empty? && target_mismatches.empty? && scenario_contract_valid
puts "Definitive audit: inventory=#{items.length} unclassified=0 targets=#{target_by_id.length} open_targets=#{target_gaps.length} scenario_proofs=#{scenario_summary.fetch('rows')} completion_eligible=0 skill_routing_gaps=#{definitive_skill.dig('summary', 'routing_gaps')} verdict=pending"
