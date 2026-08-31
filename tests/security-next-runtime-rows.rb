#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_next_runtime_rows"

plan = SecurityScenarioTranche.load_plan
rows = SecurityNextRuntimeRows.next_runtime_rows(plan)

abort "next runtime rows must stay completed28+refusal4" unless rows.length == 32
expected_completed_ids = plan.fetch("completed_rows").map { |row| SecurityScenarioTranche.row_id_for(row.fetch("pattern_id"), row.fetch("scenario")) }
abort "next runtime row_ids drifted" unless rows.map { |row| row.fetch("id") } == expected_completed_ids + SecurityScenarioTranche.expected_following_row_ids
abort "next runtime must preserve duplicate pattern ids across security/refusal" unless rows.map { |row| row.fetch("pattern_id") }.uniq.length == 28
abort "next runtime trailing refusal rows drifted" unless rows.last(4).map { |row| row.fetch("id") } == SecurityScenarioTranche.expected_following_row_ids &&
  rows.last(4).all? { |row| row.fetch("scenario") == "refusal" }
abort "next runtime unsupported scenario set drifted" unless SecurityNextRuntimeRows.unsupported_scenarios(rows) == ["refusal"]

collapsed = rows.each_with_object({}) { |row, memo| memo[row.fetch("pattern_id")] = row }.values
begin
  SecurityNextRuntimeRows.verify_selected_rows!(collapsed, plan: plan)
  abort "pattern-id collapse unexpectedly accepted"
rescue RuntimeError => e
  raise unless e.message.include?("row_ids drifted")
end

scenario_weakened = JSON.parse(JSON.generate(rows))
scenario_weakened.last["scenario"] = "security"
begin
  SecurityNextRuntimeRows.verify_selected_rows!(scenario_weakened, plan: plan)
  abort "scenario relabel unexpectedly accepted"
rescue RuntimeError => e
  raise unless e.message.include?("trailing refusal rows drifted")
end

puts "Security next runtime row selectionを検証しました: completed28+refusal4 ordering is fixed, duplicate pattern IDs remain scenario-aware, and collapse/relabel regressions are rejected"
