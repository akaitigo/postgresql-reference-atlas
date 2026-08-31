#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_scenario_tranche"

plan = SecurityScenarioTranche.load_plan
SecurityScenarioTranche.verify_completed_suite!(plan)
SecurityScenarioTranche.verify_next_tranche!(plan)

expected_row_ids = SecurityScenarioTranche.expected_row_ids
actual_row_ids = plan.dig("next_tranche", "row_ids")
abort "security tranche row selection drifted" unless actual_row_ids == expected_row_ids
following = SecurityScenarioTranche.verify_next_runtime_tranche!(plan)
abort "following security tranche row selection drifted" unless following.fetch("row_ids") == SecurityScenarioTranche.expected_following_row_ids

published_pattern_ids = SecurityScenarioTranche.published_pattern_ids(plan)
abort "security published suite selector drifted" unless published_pattern_ids == SecurityScenarioTranche::COMPLETED_PATTERN_IDS
abort "security published suite cardinality drifted" unless published_pattern_ids.length == 28 && published_pattern_ids.uniq.length == 28

runtime_pattern_ids = SecurityScenarioTranche.next_runtime_pattern_ids(plan)
abort "security next runtime selector drifted" unless runtime_pattern_ids == SecurityScenarioTranche::COMPLETED_PATTERN_IDS + SecurityScenarioTranche::FOLLOWING_TRANCHE_PATTERN_IDS
abort "security next runtime selector cardinality drifted" unless runtime_pattern_ids.length == 32

oversized = JSON.parse(JSON.generate(plan))
oversized.fetch("next_tranche").fetch("row_ids").concat([
  "closure.definitive-domain.query.sql-commands.security",
  "closure.definitive-domain.query.sql-surface.security",
  "closure.definitive-domain.query.types-constraints.security",
  "closure.definitive-domain.query.partitioning.security"
])
oversized.fetch("next_tranche")["pattern_rows"] = oversized.fetch("next_tranche").fetch("row_ids").length
oversized.fetch("next_tranche")["variant_runs"] = oversized.fetch("next_tranche").fetch("row_ids").length
begin
  SecurityScenarioTranche.verify_next_tranche!(oversized)
  abort "oversized security tranche was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("within 4 pattern rows")
end

reordered = JSON.parse(JSON.generate(plan))
reordered.fetch("next_tranche")["row_ids"] = ["closure.definitive-domain.query.partitioning.security"]
begin
  SecurityScenarioTranche.verify_next_tranche!(reordered)
  abort "reordered security tranche was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("approved order")
end

deleted = JSON.parse(JSON.generate(plan))
deleted.fetch("next_tranche")["row_ids"] = []
deleted.fetch("next_tranche")["pattern_rows"] = 0
deleted.fetch("next_tranche")["variant_runs"] = 0
begin
  SecurityScenarioTranche.verify_next_tranche!(deleted)
  abort "deleted security tranche row was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("approved order")
end

replaced = JSON.parse(JSON.generate(plan))
replaced.fetch("next_tranche")["row_ids"][-1] = SecurityScenarioTranche.expected_following_row_ids.first
begin
  SecurityScenarioTranche.verify_next_tranche!(replaced)
  abort "replaced security tranche row was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("approved order")
end

puts "Security tranche contractを検証しました: completed=28 next=1 next_runtime=32 negatives=4/4"
