#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_runtime_readiness_contract"

contract = SecurityRuntimeReadinessContract.contract
plan = SecurityScenarioTranche.load_plan
SecurityRuntimeReadinessContract.verify_contract!(contract, plan: plan)

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
abort "security runner must bind runtime readiness preflight" unless source.include?('require_relative "lib/security_runtime_readiness_contract"') && source.include?("SecurityRuntimeReadinessContract.verify_runnable!(plan: plan)")

abort "runtime readiness must remain fail-closed until next 4 row-specific contracts are authored" unless contract.fetch("status") == "not-ready"
abort "runtime readiness rows must stay exact 4" unless contract.fetch("row_ids").length == 4
abort "runtime readiness summary drifted" unless contract.fetch("summary") == {
  "completed_dedicated_rows"=>24,
  "remaining_rows"=>266,
  "planned_tranches"=>74
}
abort "runtime readiness row_ids must stay bound to next_tranche" unless contract.fetch("row_ids") == plan.dig("next_tranche", "row_ids")
abort "runtime readiness blockers drifted" unless contract.fetch("blocked_by") == [
  "next-security-row-contracts-not-authored",
  "next-security-runtime-oracles-not-authored",
  "next-security-runtime-support-paths-not-bound"
]

begin
  SecurityRuntimeReadinessContract.verify_runnable!(plan: plan)
  abort "runtime readiness unexpectedly allowed heavy rerun"
rescue RuntimeError => e
  raise unless e.message.include?("not complete")
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
summary_drift.fetch("summary")["remaining_rows"] = 270
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

puts "security runtime readiness contractを検証しました: next 4 rows stay fail-closed, summary 24/266/74 is fixed, and status/row/blocker drift is rejected"
