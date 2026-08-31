#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_next_tranche_row_contracts"

contract = SecurityNextTrancheRowContracts.contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.types-constraints" } or abort("query.types-constraints row contract missing")
abort "query.types-constraints row contract target drifted" unless contract.fetch("target_id") == "query.types-constraints"
abort "query.types-constraints row contract proof obligation drifted" unless contract.fetch("proof_obligation_id") == "query.types-constraints"
abort "query.types-constraints row contract must keep uuidv7/generated/literal-tenant SQL" unless contract.fetch("sql_fragments").include?("DEFAULT uuidv7()") && contract.fetch("sql_fragments").include?("GENERATED ALWAYS AS (metadata ->> 'name') STORED") && contract.fetch("sql_fragments").include?("USING (tenant = 'atlas_typed_order_writer')")
abort "query.types-constraints row contract must forbid current_user/BYPASSRLS regressions" unless contract.fetch("forbidden_sql_fragments").include?("current_user") && contract.fetch("forbidden_sql_fragments").include?("ALTER ROLE atlas_typed_order_writer BYPASSRLS")
abort "query.types-constraints row contract must require observation, invalid-domain, and generated-value predicates" unless contract.fetch("required_oracle_predicates").include?("observation_rows_exact") && contract.fetch("required_oracle_predicates").include?("invalid_domain_sqlstate_exact") && contract.fetch("required_oracle_predicates").include?("generated_value_exact")
abort "query.types-constraints row contract must reject invalid-domain, observation, nested PL/pgSQL shape, semicolon, and generic-mapping drift" unless contract.fetch("negative_cases").include?("invalid_domain_not_rejected") && contract.fetch("negative_cases").include?("uuid_version_drift") && contract.fetch("negative_cases").include?("do_semicolon_missing") && contract.fetch("negative_cases").include?("observation_insert_missing") && contract.fetch("negative_cases").include?("observation_duplicate_seed") && contract.fetch("negative_cases").include?("tenant_observation_insert_allowed") && contract.fetch("negative_cases").include?("observation_update_zero_rows") && contract.fetch("negative_cases").include?("observation_final_zero_rows") && contract.fetch("negative_cases").include?("observation_final_multiple_rows") && contract.fetch("negative_cases").include?("generic_unknown_failure_mapping") && contract.fetch("negative_cases").include?("first_nested_begin_missing") && contract.fetch("negative_cases").include?("sibling_refusal_block_outside_outer_do")

weakened_sql = JSON.parse(JSON.generate(contract))
weakened_sql.fetch("sql_fragments").delete("DEFAULT uuidv7()")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_sql, contract)
  abort "weakened query.types-constraints SQL was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sql_fragments drifted")
end

weakened_oracle = JSON.parse(JSON.generate(contract))
weakened_oracle.fetch("required_oracle_predicates").delete("uuid_v7_exact")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_oracle, contract)
  abort "weakened query.types-constraints oracle predicates were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("required_oracle_predicates drifted")
end

weakened_negative = JSON.parse(JSON.generate(contract))
weakened_negative.fetch("negative_cases").delete("other_tenant_insert_allowed")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_negative, contract)
  abort "weakened query.types-constraints negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negative_cases drifted")
end

puts "query.types-constraints next tranche contractを検証しました: uuid/domain/generated-value, observation cardinality, and structured failure guards are fixed"
