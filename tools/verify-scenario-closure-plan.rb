#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/scenario_closure_plan"

actual = ScenarioClosurePlan.load_json(ScenarioClosurePlan::PLAN_PATH)
expected = ScenarioClosurePlan.build
abort "Scenario Closure Plan is stale or edited outside its generator" unless actual == expected
summary = actual.fetch("summary")
abort "PostgreSQL Scenario denominator drift" unless summary.fetch("remaining_rows") == 278 && summary.fetch("by_scenario").fetch("security") == 17 && summary.fetch("by_scenario").reject { |scenario, _| scenario == "security" }.values == Array.new(9, 29)
abort "PostgreSQL completed suite overclaim" unless summary.fetch("completed_dedicated_rows") == 12 && actual.fetch("completed_rows").length == 12 && actual.fetch("completed_rows").all? { |row| row.fetch("scenario") == "security" && row.fetch("all_first_attempt_pass") && row.fetch("all_trace_streams") && row.fetch("variant_ids") == ["postgresql-verification-matrix-v2"] }
abort "Tranche contract" unless summary.fetch("planned_tranches") == 77 && actual.fetch("tranches").all? { |tranche| tranche.fetch("pattern_rows").between?(1, 4) && tranche.fetch("variant_runs") >= tranche.fetch("pattern_rows") }
abort "Next risk tranche" unless actual.dig("next_tranche", "id") == "security-001"
abort "Closure contract weakened" unless actual.fetch("rows").all? do |row|
  closure = row.fetch("required_closure")
  !row.fetch("variant_ids").empty? && closure == ScenarioClosurePlan::REQUIRED_CLOSURE
end
abort "Independent incomplete axes were closed" unless actual.dig("independent_incomplete", "authority_atomic_rows") == 0 && actual.dig("independent_incomplete", "external_profiles").length == 4
puts "Verified PostgreSQL Scenario Closure Plan: remaining=#{summary.fetch('remaining_rows')} completed=#{summary.fetch('completed_dedicated_rows')} tranches=#{summary.fetch('planned_tranches')} maximum_rows=4 next=security-001"
