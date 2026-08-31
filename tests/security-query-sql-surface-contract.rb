#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_next_tranche_row_contracts"

contract = SecurityNextTrancheRowContracts.contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.sql-surface" } or abort("query.sql-surface row contract missing")
abort "query.sql-surface row contract target drifted" unless contract.fetch("target_id") == "query.sql-surface"
abort "query.sql-surface row contract proof obligation drifted" unless contract.fetch("proof_obligation_id") == "query.constraints-and-returning"
abort "query.sql-surface row contract must keep exact literal tenant policy and RETURNING SQL" unless contract.fetch("sql_fragments").include?("USING (tenant = 'atlas_sql_surface_writer')") && contract.fetch("sql_fragments").include?("RETURNING id, note")
abort "query.sql-surface row contract must forbid current_user and UPDATE grant regressions" unless contract.fetch("forbidden_sql_fragments").include?("current_user") && contract.fetch("forbidden_sql_fragments").include?("GRANT UPDATE")
abort "query.sql-surface row contract must require observation and duplicate/check SQLSTATE predicates" unless contract.fetch("required_oracle_predicates").include?("observation_rows_exact") && contract.fetch("required_oracle_predicates").include?("duplicate_key_sqlstate_exact") && contract.fetch("required_oracle_predicates").include?("check_violation_sqlstate_exact")
abort "query.sql-surface row contract must reject other-tenant insert, observation, same-statement snapshot, nested PL/pgSQL shape, semicolon, and generic-mapping regressions" unless contract.fetch("negative_cases").include?("other_tenant_insert_allowed") && contract.fetch("negative_cases").include?("public_policy_regression") && contract.fetch("negative_cases").include?("do_semicolon_missing") && contract.fetch("negative_cases").include?("observation_insert_missing") && contract.fetch("negative_cases").include?("observation_duplicate_seed") && contract.fetch("negative_cases").include?("tenant_observation_insert_allowed") && contract.fetch("negative_cases").include?("observation_update_zero_rows") && contract.fetch("negative_cases").include?("observation_final_zero_rows") && contract.fetch("negative_cases").include?("observation_final_multiple_rows") && contract.fetch("negative_cases").include?("generic_unknown_failure_mapping") && contract.fetch("negative_cases").include?("first_nested_begin_missing") && contract.fetch("negative_cases").include?("sibling_refusal_block_outside_outer_do") && contract.fetch("negative_cases").include?("same_statement_visibility_snapshot_regression")

weakened_sql = JSON.parse(JSON.generate(contract))
weakened_sql.fetch("sql_fragments").delete("WITH CHECK (tenant = 'atlas_sql_surface_writer')")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_sql, contract)
  abort "weakened query.sql-surface SQL was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sql_fragments drifted")
end

weakened_oracle = JSON.parse(JSON.generate(contract))
weakened_oracle.fetch("required_oracle_predicates").delete("literal_tenant_policy_exact")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_oracle, contract)
  abort "weakened query.sql-surface oracle predicates were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("required_oracle_predicates drifted")
end

weakened_negative = JSON.parse(JSON.generate(contract))
weakened_negative.fetch("negative_cases").delete("grant_update_regression")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_negative, contract)
  abort "weakened query.sql-surface negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negative_cases drifted")
end

puts "query.sql-surface next tranche contractを検証しました: RETURNING, observation cardinality, and structured failure guards are fixed"
