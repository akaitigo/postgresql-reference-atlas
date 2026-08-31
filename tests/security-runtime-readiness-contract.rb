#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_runtime_readiness_contract"

contract = SecurityRuntimeReadinessContract.contract
plan = SecurityScenarioTranche.load_plan
SecurityRuntimeReadinessContract.verify_contract!(contract, plan: plan)
root = SecurityRuntimeReadinessContract::ROOT
token_env = SecurityRuntimeReadinessContract::SLOT_TOKEN_ENV
now = Time.utc(2026, 8, 31, 12, 0, 0)
live_env = { token_env=>"security-slot-001" }
live_measurements = { "free_gib"=>4.5, "docker_active_containers"=>0 }

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
abort "security runner must bind runtime readiness preflight" unless source.include?('require_relative "lib/security_runtime_readiness_contract"') &&
  source.include?("SecurityRuntimeReadinessContract.evaluate_live_preflight!(plan: plan)") &&
  source.include?("SecurityRuntimeReadinessContract.verify_runnable!(plan: plan, preflight: runtime_preflight)")

abort "runtime readiness must remain fail-closed until a live same-run slot context is provided" unless contract.fetch("status") == "not-ready"
abort "runtime readiness rows must stay exact 4" unless contract.fetch("row_ids").length == 4
abort "runtime readiness must fix exact heavy command" unless contract.fetch("command") == "ruby tools/run-scenario-security-001.rb"
abort "runtime readiness must require exclusive heavy slot and >=4 GiB free" unless contract.fetch("runtime_prerequisites") == {
  "exclusive_heavy_slot_required"=>true,
  "minimum_free_gib"=>4,
  "docker_active_containers"=>0
}
abort "runtime readiness expected outputs drifted" unless contract.fetch("expected_outputs") == [
  "artifacts/pattern-scenarios/results.json",
  "artifacts/pattern-scenarios/traces/definitive-domain_query_partitioning__security__postgresql-verification-matrix-v2.trace.json",
  "artifacts/pattern-scenarios/traces/definitive-domain_query_security__security__postgresql-verification-matrix-v2.trace.json",
  "artifacts/pattern-scenarios/traces/definitive-domain_query_sql-surface__security__postgresql-verification-matrix-v2.trace.json",
  "artifacts/pattern-scenarios/traces/definitive-domain_query_types-constraints__security__postgresql-verification-matrix-v2.trace.json",
  "artifacts/pattern-scenarios/observations/definitive-domain_query_partitioning__security__postgresql-verification-matrix-v2.observable.json",
  "artifacts/pattern-scenarios/observations/definitive-domain_query_security__security__postgresql-verification-matrix-v2.observable.json",
  "artifacts/pattern-scenarios/observations/definitive-domain_query_sql-surface__security__postgresql-verification-matrix-v2.observable.json",
  "artifacts/pattern-scenarios/observations/definitive-domain_query_types-constraints__security__postgresql-verification-matrix-v2.observable.json"
]
abort "runtime readiness summary drifted" unless contract.fetch("summary") == {
  "completed_dedicated_rows"=>28,
  "remaining_rows"=>262,
  "planned_tranches"=>73
}
completed_ids = plan.fetch("completed_rows").map { |row| SecurityScenarioTranche.row_id_for(row.fetch("pattern_id")) }
abort "runtime readiness row_ids must stay bound to the completed runtime tranche" unless contract.fetch("row_ids") == SecurityScenarioTranche.expected_latest_runtime_row_ids
abort "runtime readiness completed suite binding drifted" unless (contract.fetch("row_ids") - completed_ids).empty?
abort "runtime readiness blockers drifted" unless contract.fetch("blocked_by") == [
  "live-slot-token-and-run-context-required"
]

preflight = SecurityRuntimeReadinessContract.evaluate_live_preflight!(
  plan: plan, env: live_env, now: now, pid: 101, repo_root: root, cwd: root, measurements: live_measurements
)
abort "runtime readiness live preflight kind drifted" unless preflight.fetch("kind") == "postgresql-security-runtime-preflight-v1"
abort "runtime readiness live preflight should be ready with matching token, root, disk, docker, and attempt policy" unless preflight.fetch("status") == "ready"
abort "runtime readiness live preflight failures should be empty for the ready path" unless preflight.fetch("failures").empty?
abort "runtime readiness live preflight must bind exact outputs" unless preflight.fetch("expected_outputs") == contract.fetch("expected_outputs")
SecurityRuntimeReadinessContract.verify_preflight!(preflight, plan: plan, env: live_env, now: now, pid: 101, repo_root: root, cwd: root)
SecurityRuntimeReadinessContract.verify_runnable!(plan: plan, preflight: preflight, env: live_env, now: now, pid: 101, repo_root: root, cwd: root)

blocked = SecurityRuntimeReadinessContract.evaluate_live_preflight!(
  plan: plan, env: {}, now: now, pid: 101, repo_root: root, cwd: root, measurements: live_measurements
)
abort "runtime readiness must fail closed without slot token" unless blocked.fetch("status") == "blocked" && blocked.fetch("failures").include?("slot-token-missing-or-mismatched")

begin
  SecurityRuntimeReadinessContract.verify_runnable!(
    plan: plan, env: {}, now: now, pid: 101, repo_root: root, cwd: root, measurements: live_measurements
  )
  abort "runtime readiness unexpectedly allowed heavy rerun without live token"
rescue RuntimeError => e
  raise unless e.message.include?("slot-token-missing-or-mismatched")
end

deleted = JSON.parse(JSON.generate(contract))
deleted["row_ids"] = deleted.fetch("row_ids").first(3)
begin
  SecurityRuntimeReadinessContract.verify_contract!(deleted, plan: plan)
  abort "deleted runtime readiness row was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("row_ids drifted")
end

reordered = JSON.parse(JSON.generate(contract))
reordered["row_ids"] = reordered.fetch("row_ids").reverse
begin
  SecurityRuntimeReadinessContract.verify_contract!(reordered, plan: plan)
  abort "reordered runtime readiness rows were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("row_ids drifted")
end

ready_status = JSON.parse(JSON.generate(contract))
ready_status["status"] = "ready"
begin
  SecurityRuntimeReadinessContract.verify_contract!(ready_status, plan: plan)
  abort "runtime readiness status drift was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("status drifted")
end

summary_drift = JSON.parse(JSON.generate(contract))
summary_drift.fetch("summary")["remaining_rows"] = 266
begin
  SecurityRuntimeReadinessContract.verify_contract!(summary_drift, plan: plan)
  abort "runtime readiness summary drift was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("summary drifted")
end

blocked_by_drift = JSON.parse(JSON.generate(contract))
blocked_by_drift.fetch("blocked_by").pop
begin
  SecurityRuntimeReadinessContract.verify_contract!(blocked_by_drift, plan: plan)
  abort "runtime readiness blocked_by drift was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("blocked_by drifted")
end

output_drift = JSON.parse(JSON.generate(contract))
output_drift.fetch("expected_outputs").pop
begin
  SecurityRuntimeReadinessContract.verify_contract!(output_drift, plan: plan)
  abort "runtime readiness output drift was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("expected outputs drifted")
end

prereq_drift = JSON.parse(JSON.generate(contract))
prereq_drift.fetch("runtime_prerequisites")["minimum_free_gib"] = 3
begin
  SecurityRuntimeReadinessContract.verify_contract!(prereq_drift, plan: plan)
  abort "runtime readiness prerequisite drift was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("prerequisites drifted")
end

status_hand_edit = JSON.parse(JSON.generate(blocked))
status_hand_edit["status"] = "ready"
begin
  SecurityRuntimeReadinessContract.verify_preflight!(status_hand_edit, plan: plan, env: {}, now: now, pid: 101, repo_root: root, cwd: root)
  abort "runtime readiness status hand-edit was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("status drifted")
end

puts "security runtime readiness contractを検証しました: published query 4-row preflight remains fail-closed, and live runnable state still depends on same-run token/root/disk/docker checks"
