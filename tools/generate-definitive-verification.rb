#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"
require "yaml"

root = File.expand_path("..", __dir__)
coverage = YAML.safe_load(File.read(File.join(root, "coverage.yaml")), aliases: false)
claims = Dir.glob(File.join(root, "claims/*.claim.yaml")).to_h do |path|
  claim = YAML.safe_load(File.read(path), aliases: false)
  [claim.fetch("id"), claim]
end
evidence = Dir.glob(File.join(root, "evidence/*.evidence.yaml")).to_h do |path|
  record = YAML.safe_load(File.read(path), aliases: false)
  [record.fetch("id"), record]
end

scenario_hints = {
  "foundation.version-lock"=>%w[normal compatibility], "foundation.authority-lock"=>%w[normal compatibility],
  "query.sql-surface"=>%w[normal rejection], "query.types-constraints"=>%w[normal boundary rejection],
  "query.catalog-inventory"=>%w[normal compatibility], "query.partitioning"=>%w[normal boundary performance],
  "query.extension"=>%w[normal rejection performance], "query.security"=>%w[normal rejection security],
  "concurrency.mvcc"=>%w[normal boundary], "concurrency.locking"=>%w[rejection failure recovery],
  "concurrency.deadlock"=>%w[failure recovery], "performance.planner"=>%w[normal performance],
  "performance.statistics"=>%w[normal performance], "performance.index"=>%w[normal performance],
  "performance.execution"=>%w[normal performance], "operations.backup-recovery"=>%w[normal recovery],
  "operations.observability"=>%w[normal operations], "operations.wal"=>%w[normal operations],
  "operations.pitr-recovery"=>%w[failure recovery], "operations.replication"=>%w[normal failure recovery],
  "operations.logical-replication"=>%w[normal failure recovery], "operations.failure-injection"=>%w[failure recovery],
  "operations.maintenance"=>%w[normal operations recovery], "lifecycle.schema-migration"=>%w[normal migration recovery],
  "lifecycle.upgrade"=>%w[normal migration compatibility], "lifecycle.pg-upgrade"=>%w[migration compatibility recovery],
  "lifecycle.compatibility-matrix"=>%w[normal compatibility], "skill.router-evaluation"=>%w[normal rejection],
  "publication.provenance"=>%w[normal rejection]
}.freeze

rows = coverage.fetch("targets").flat_map do |target|
  scenarios = scenario_hints.fetch(target.fetch("id"), [])
  next [] if scenarios.empty? || target.fetch("evidence_ids").empty? || target.fetch("claim_ids").empty?
  claim = claims[target.fetch("claim_ids").first]
  next [] unless claim
  proof_id = claim.fetch("proof_obligations").first.fetch("id")
  usable_evidence = target.fetch("evidence_ids").select { |id| evidence[id]&.fetch("verdict") == "pass" }
  next [] if usable_evidence.empty?
  scenarios.map do |scenario|
    profile = evidence.fetch(usable_evidence.first).dig("environment", "profile")
    {
      "behavior_id"=>"definitive-domain.#{target.fetch("id")}","scenario"=>scenario,"applicability"=>"required",
      "rationale"=>"v1で実行済みの証拠がこのScenarioの限定的なBehaviorを立証するため再利用する。",
      "proof_obligation_id"=>proof_id,"evidence_ids"=>usable_evidence,"execution_requirement"=>(scenario == "compatibility" ? "platform" : "runtime"),"profile"=>profile
    }
  end
end
matrix = {"schema_version"=>2,"atlas_id"=>"postgresql-reference-atlas","epoch"=>"2026-08-28","rows"=>rows}
File.write(File.join(root, "verification.matrix.yaml"), JSON.parse(JSON.generate(matrix)).to_yaml(line_width: -1))

router_report = JSON.parse(File.read(File.join(root, "evidence/artifacts/skill-router-eval.json")))
surface_by_capability = {
  "coverage-gap"=>%w[orientation-scope agent-skill], "query.security"=>%w[security-privacy-safety testing-verification],
  "performance.index"=>%w[performance-capacity-cost decision-comparison], "performance.planner"=>%w[performance-capacity-cost operations-observability],
  "operations.replication"=>%w[operations-observability failure-recovery], "operations.pitr-recovery"=>%w[failure-recovery operations-observability],
  "lifecycle.upgrade"=>%w[migration-evolution-deprecation compatibility-integration]
}
cases = router_report.fetch("results").map do |result|
  outcome = result.fetch("outcome")
  {
    "id"=>"definitive.#{result.fetch("id")}","result"=>result.fetch("verdict"),"outcome_ids"=>[outcome],
    "surface_ids"=>surface_by_capability.fetch(result.fetch("capability"), %w[testing-verification agent-skill]),
    "gap_behavior"=>result.fetch("coverage") == "outside","authorization_boundary"=>%w[stop read-only-first].include?(result.fetch("safety")),
    "assertion"=>"#{result.fetch("id")}はv1 Routerの期待Capabilityと安全境界へ到達する。"
  }
end
skill_eval = {"schema_version"=>2,"id"=>"skill.postgresql-definitive-audit","atlas_id"=>"postgresql-reference-atlas","atlas_release"=>"v1.0.0","skill_id"=>"postgresql-atlas","generated_at"=>Time.now.utc.iso8601,"cases"=>cases}
File.write(File.join(root, "evals/postgresql-atlas.definitive-skill-eval.json"), JSON.pretty_generate(skill_eval) + "\n")
puts "Verification Matrix: #{rows.length} rows; Definitive Skill Eval baseline: #{cases.length} cases"
