#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_next_tranche_row_contracts"

contract = SecurityNextTrancheRowContracts.contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.security" } or abort("query.security row contract missing")
abort "query.security row contract target drifted" unless contract.fetch("target_id") == "query.security"
abort "query.security row contract proof obligation drifted" unless contract.fetch("proof_obligation_id") == "query.rls-boundary"
abort "query.security row contract must keep FORCE RLS and WITH CHECK SQL" unless contract.fetch("sql_fragments").include?("ALTER TABLE tenant_record FORCE ROW LEVEL SECURITY;") && contract.fetch("sql_fragments").include?("current_setting('app.tenant_id')::integer")
abort "query.security row contract must keep committed bootstrap and exact loopback dblink target" unless contract.fetch("sql_fragments").include?("COMMIT;") && contract.fetch("sql_fragments").include?("SELECT dblink_connect('tenant1', 'host=127.0.0.1 dbname=atlas user=tenant_app password=tenant-atlas options=-capp.tenant_id=1');")
abort "query.security row contract must forbid BYPASSRLS, row_security=off, and wrong dblink targets" unless contract.fetch("forbidden_sql_fragments").include?("ALTER ROLE tenant_app BYPASSRLS") && contract.fetch("forbidden_sql_fragments").include?("SET row_security = off") && contract.fetch("forbidden_sql_fragments").include?("dbname=postgres") && contract.fetch("forbidden_sql_fragments").include?("host=/tmp")
abort "query.security row contract must require ordered host-rule/search_path/scram predicates" unless contract.fetch("required_oracle_predicates").include?("observation_rows_exact") && contract.fetch("required_oracle_predicates").include?("sqlstate_42501") && contract.fetch("required_oracle_predicates").include?("scram_verifier_true") && contract.fetch("required_oracle_predicates").include?("host_rule_rows_present") && contract.fetch("required_oracle_predicates").include?("effective_host_rule_present") && contract.fetch("required_oracle_predicates").include?("effective_host_rule_auth_method_scram") && contract.fetch("required_oracle_predicates").include?("effective_host_rule_error_blank") && contract.fetch("required_oracle_predicates").include?("fixed_search_path_true")
abort "query.security row contract must reject precommit dblink, ordered auth-path drift, cross-tenant, observation-row drift, search_path, and JSON parse drift" unless contract.fetch("negative_cases").include?("precommit_dblink_visibility") && contract.fetch("negative_cases").include?("missing_host_target") && contract.fetch("negative_cases").include?("wrong_db_target") && contract.fetch("negative_cases").include?("wrong_dblink_password") && contract.fetch("negative_cases").include?("wrong_socket_target") && contract.fetch("negative_cases").include?("initdb_auth_args_missing") && contract.fetch("negative_cases").include?("localhost_trust_precedes") && contract.fetch("negative_cases").include?("host_scram_append_only") && contract.fetch("negative_cases").include?("host_auth_rule_order_reversed") && contract.fetch("negative_cases").include?("host_auth_trust") && contract.fetch("negative_cases").include?("host_auth_md5") && contract.fetch("negative_cases").include?("host_auth_method_null") && contract.fetch("negative_cases").include?("host_auth_error_present") && contract.fetch("negative_cases").include?("host_scram_false_positive") && contract.fetch("negative_cases").include?("cross_tenant_insert_allowed") && contract.fetch("negative_cases").include?("search_path_drift") && contract.fetch("negative_cases").include?("observation_insert_missing") && contract.fetch("negative_cases").include?("tenant_observation_insert_allowed") && contract.fetch("negative_cases").include?("observation_update_zero_rows") && contract.fetch("negative_cases").include?("observation_final_zero_rows") && contract.fetch("negative_cases").include?("observation_final_multiple_rows") && contract.fetch("negative_cases").include?("missing_json_result") && contract.fetch("negative_cases").include?("marker_only_result") && contract.fetch("negative_cases").include?("non_object_json_result") && contract.fetch("negative_cases").include?("multiple_json_candidates") && contract.fetch("negative_cases").include?("truncated_json_result")

weakened_sql = JSON.parse(JSON.generate(contract))
weakened_sql.fetch("sql_fragments").delete("ALTER TABLE tenant_record FORCE ROW LEVEL SECURITY;")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_sql, contract)
  abort "weakened query.security SQL was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sql_fragments drifted")
end

weakened_oracle = JSON.parse(JSON.generate(contract))
weakened_oracle.fetch("required_oracle_predicates").delete("host_scram_rule_true")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_oracle, contract)
  abort "weakened query.security oracle predicates were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("required_oracle_predicates drifted")
end

weakened_negative = JSON.parse(JSON.generate(contract))
weakened_negative.fetch("negative_cases").delete("bypassrls_regression")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_negative, contract)
  abort "weakened query.security negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negative_cases drifted")
end

puts "query.security next tranche contractを検証しました: FORCE RLS, scram/search_path, and cross-tenant refusal guards are fixed"
