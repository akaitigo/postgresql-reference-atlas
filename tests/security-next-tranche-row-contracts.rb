#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_next_tranche_row_contracts"

contracts = SecurityNextTrancheRowContracts.contracts
SecurityNextTrancheRowContracts.verify!(contracts)

abort "next tranche row contracts must stay exact 4 rows" unless contracts.length == 4
abort "next tranche row ids must stay bound to the published runtime tranche order" unless SecurityNextTrancheRowContracts.row_ids(contracts) == SecurityScenarioTranche.expected_latest_runtime_row_ids

partitioning = contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.partitioning" } or abort("partitioning row contract missing")
abort "partitioning row contract must require detach rejection" unless partitioning.fetch("negative_cases").include?("detach_partition_allowed")
abort "partitioning row contract must keep pruning plan predicates" unless partitioning.fetch("required_oracle_predicates").include?("plan_q1_partition_present")

security = contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.security" } or abort("query.security row contract missing")
abort "query.security row contract must require FORCE RLS" unless security.fetch("negative_cases").include?("force_rls_missing")
abort "query.security row contract must bind fixed search_path proof" unless security.fetch("required_oracle_predicates").include?("fixed_search_path_true")

sql_surface = contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.sql-surface" } or abort("query.sql-surface row contract missing")
abort "query.sql-surface row contract must reject current_user policy regressions" unless sql_surface.fetch("negative_cases").include?("current_user_policy_regression")
abort "query.sql-surface row contract must require RETURNING" unless sql_surface.fetch("sql_fragments").include?("RETURNING id, note")
abort "query.sql-surface row contract must pin nested sibling PL/pgSQL refusal blocks" unless sql_surface.fetch("negative_cases").include?("first_nested_begin_missing") && sql_surface.fetch("negative_cases").include?("sibling_refusal_block_outside_outer_do")
abort "query.sql-surface row contract must pin same-statement visibility snapshot regressions" unless sql_surface.fetch("negative_cases").include?("same_statement_visibility_snapshot_regression")

types_constraints = contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.types-constraints" } or abort("query.types-constraints row contract missing")
abort "query.types-constraints row contract must reject invalid domain acceptance" unless types_constraints.fetch("negative_cases").include?("invalid_domain_not_rejected")
abort "query.types-constraints row contract must require uuidv7" unless types_constraints.fetch("sql_fragments").include?("DEFAULT uuidv7()")
abort "query.types-constraints row contract must pin nested sibling PL/pgSQL refusal blocks" unless types_constraints.fetch("negative_cases").include?("first_nested_begin_missing") && types_constraints.fetch("negative_cases").include?("sibling_refusal_block_outside_outer_do")

deleted = JSON.parse(JSON.generate(contracts))
deleted.pop
begin
  SecurityNextTrancheRowContracts.verify!(deleted)
  abort "deleted next tranche row contract was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("cardinality drifted")
end

reordered = JSON.parse(JSON.generate(contracts))
reordered.reverse!
begin
  SecurityNextTrancheRowContracts.verify!(reordered)
  abort "reordered next tranche row contracts were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("pattern order drifted")
end

weakened_sql = JSON.parse(JSON.generate(contracts))
weakened_sql.first.fetch("sql_fragments").delete("ALTER TABLE atlas_partition_secure DETACH PARTITION atlas_partition_secure_2026q1")
begin
  SecurityNextTrancheRowContracts.verify!(weakened_sql)
  abort "weakened next tranche row SQL fragment was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sql_fragments drifted")
end

weakened_oracle = JSON.parse(JSON.generate(contracts))
weakened_oracle[1].fetch("required_oracle_predicates").delete("fixed_search_path_true")
begin
  SecurityNextTrancheRowContracts.verify!(weakened_oracle)
  abort "weakened next tranche row oracle predicates were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("required_oracle_predicates drifted")
end

weakened_negative = JSON.parse(JSON.generate(contracts))
weakened_negative[2].fetch("negative_cases").delete("other_tenant_insert_allowed")
begin
  SecurityNextTrancheRowContracts.verify!(weakened_negative)
  abort "weakened next tranche row negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negative_cases drifted")
end

weakened_support = JSON.parse(JSON.generate(contracts))
weakened_support[3].fetch("support_paths").delete("labs/types-constraints/verify.sql")
begin
  SecurityNextTrancheRowContracts.verify!(weakened_support)
  abort "weakened next tranche support path binding was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("support_paths drifted")
end

puts "Security runtime row contractsを検証しました: exact published query 4 rows keep SQL/oracle/negative/support-path guards"
