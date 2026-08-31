#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/scenario_closure_plan"
require_relative "lib/security_scenario_tranche"

actual = ScenarioClosurePlan.load_json(ScenarioClosurePlan::PLAN_PATH)
expected = ScenarioClosurePlan.build
abort "Scenario Closure Plan is stale or edited outside its generator" unless actual == expected
summary = actual.fetch("summary")
completed_rows = SecurityScenarioTranche::COMPLETED_PATTERN_IDS.length
remaining_rows = 290 - completed_rows
remaining_security_rows = 29 - completed_rows
abort "PostgreSQL Scenario denominator drift" unless summary.fetch("remaining_rows") == remaining_rows && summary.fetch("by_scenario").fetch("security") == remaining_security_rows && summary.fetch("by_scenario").reject { |scenario, _| scenario == "security" }.values == Array.new(9, 29)
abort "PostgreSQL completed suite overclaim" unless summary.fetch("completed_dedicated_rows") == completed_rows && actual.fetch("completed_rows").length == completed_rows && actual.fetch("completed_rows").all? { |row| row.fetch("scenario") == "security" && row.fetch("all_first_attempt_pass") && row.fetch("all_trace_streams") && row.fetch("variant_ids") == ["postgresql-verification-matrix-v2"] }
abort "Tranche contract" unless summary.fetch("planned_tranches") == actual.fetch("tranches").length && actual.fetch("tranches").all? { |tranche| tranche.fetch("pattern_rows").between?(1, 4) && tranche.fetch("variant_runs") >= tranche.fetch("pattern_rows") }
abort "Next risk tranche" unless actual.dig("next_tranche", "id") == "security-001"
abort "Closure contract weakened" unless actual.fetch("rows").all? do |row|
  closure = row.fetch("required_closure")
  !row.fetch("variant_ids").empty? && closure == ScenarioClosurePlan::REQUIRED_CLOSURE
end
abort "Independent incomplete axes were closed" unless actual.dig("independent_incomplete", "authority_atomic_rows") == 0 && actual.dig("independent_incomplete", "external_profiles").length == 4
SecurityScenarioTranche.verify_next_tranche!(actual)
SecurityScenarioTranche.verify_following_tranche!(actual)

oversized = JSON.parse(JSON.generate(actual))
oversized.fetch("next_tranche").fetch("row_ids") << "closure.definitive-domain.query.sql-commands.security"
oversized.fetch("next_tranche")["pattern_rows"] = oversized.fetch("next_tranche").fetch("row_ids").length
oversized.fetch("next_tranche")["variant_runs"] = oversized.fetch("next_tranche").fetch("row_ids").length
begin
  SecurityScenarioTranche.verify_next_tranche!(oversized)
  abort "oversized security tranche was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("within 4 pattern rows")
end

reordered = JSON.parse(JSON.generate(actual))
reordered.fetch("next_tranche")["row_ids"] = reordered.fetch("next_tranche").fetch("row_ids").reverse
begin
  SecurityScenarioTranche.verify_next_tranche!(reordered)
  abort "reordered security tranche was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("approved order")
end

deleted = JSON.parse(JSON.generate(actual))
deleted.fetch("next_tranche")["row_ids"] = deleted.fetch("next_tranche").fetch("row_ids")[0, 3]
deleted.fetch("next_tranche")["pattern_rows"] = 3
deleted.fetch("next_tranche")["variant_runs"] = 3
begin
  SecurityScenarioTranche.verify_next_tranche!(deleted)
  abort "deleted security tranche row was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("approved order")
end

replaced = JSON.parse(JSON.generate(actual))
replaced.fetch("next_tranche")["row_ids"][-1] = SecurityScenarioTranche.expected_following_row_ids.first
begin
  SecurityScenarioTranche.verify_next_tranche!(replaced)
  abort "replaced security tranche row was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("approved order")
end

puts "Verified PostgreSQL Scenario Closure Plan: remaining=#{summary.fetch('remaining_rows')} completed=#{summary.fetch('completed_dedicated_rows')} tranches=#{summary.fetch('planned_tranches')} maximum_rows=4 next=security-001"
