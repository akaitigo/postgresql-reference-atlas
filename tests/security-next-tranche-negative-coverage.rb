#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_next_tranche_row_contracts"

ROOT = File.expand_path("..", __dir__)

TEST_PATHS = {
  "definitive-domain.query.partitioning"=>[
    "tests/security-query-partitioning-contract.rb",
    "tests/security-query-partitioning-sql-contract.rb",
    "tests/security-next-tranche-runtime-hygiene.rb",
    "tests/security-next-tranche-oracles.rb"
  ],
  "definitive-domain.query.security"=>[
    "tests/security-query-security-contract.rb",
    "tests/security-query-security-sql-contract.rb",
    "tests/security-query-security-runtime-auth-contract.rb",
    "tests/security-query-security-json-contract.rb",
    "tests/security-next-tranche-oracles.rb"
  ],
  "definitive-domain.query.sql-surface"=>[
    "tests/security-query-sql-surface-contract.rb",
    "tests/security-query-sql-surface-sql-contract.rb",
    "tests/security-next-tranche-runtime-hygiene.rb",
    "tests/security-next-tranche-oracles.rb"
  ],
  "definitive-domain.query.types-constraints"=>[
    "tests/security-query-types-constraints-contract.rb",
    "tests/security-query-types-constraints-sql-contract.rb",
    "tests/security-next-tranche-runtime-hygiene.rb",
    "tests/security-next-tranche-oracles.rb"
  ]
}.freeze

TOKENS = {
  "definitive-domain.query.partitioning"=>{
    "detach_partition_allowed"=>["detach", "unexpectedly allowed"],
    "partition_pruning_missing"=>["partition_pruning", "pruning false"],
    "q1_partition_missing"=>["q1_partition_present", "q1_rows_exact"],
    "q2_partition_visible"=>["q2 leak", "plan_q2_partition_absent"],
    "default_partition_visible"=>["default partition leak", "plan_default_partition_absent"],
    "do_semicolon_missing"=>["END;", "terminate every DO block"],
    "observation_duplicate_seed"=>["seed expected 1 row", "seed exactly one observation row"],
    "tenant_observation_insert_allowed"=>["GRANT ALL ON atlas_partition_observation", "must not allow tenant observation inserts"],
    "observation_update_zero_rows"=>["ROW_COUNT", "atlas_partition_observation plan update expected 1 row"],
    "observation_final_zero_rows"=>["final cardinality expected 1 row", "final observation cardinality"],
    "observation_final_multiple_rows"=>["final cardinality expected 1 row", "final observation cardinality"],
    "generic_unknown_failure_mapping"=>["psql_json_execution_for_row!(", "row-specific failure binding"],
    "forced_partition_guc_present"=>["enable_partition_pruning = off", "forced_partition_guc_present"]
  },
  "definitive-domain.query.security"=>{
    "force_rls_missing"=>["FORCE ROW LEVEL SECURITY", "force_rls_missing"],
    "with_check_missing"=>["WITH CHECK", "current_setting('app.tenant_id')::integer"],
    "bypassrls_regression"=>["BYPASSRLS", "bypassrls_regression"],
    "precommit_dblink_visibility"=>["COMMIT;", "commit bootstrap"],
    "missing_host_target"=>["host=127.0.0.1", "missing host"],
    "wrong_db_target"=>["dbname=postgres", "wrong database"],
    "wrong_dblink_password"=>["password=tenant-wrong", "wrong password"],
    "wrong_socket_target"=>["host=/tmp", "socket path"],
    "initdb_auth_args_missing"=>["POSTGRES_INITDB_ARGS", "initdb args"],
    "localhost_trust_precedes"=>["127.0.0.1/32", "localhost trust"],
    "host_scram_append_only"=>["scram append-only", "first matching rule"],
    "host_auth_rule_order_reversed"=>["ORDER BY line_number", "rule order"],
    "host_auth_trust"=>["auth_method = 'trust'", "host trust"],
    "host_auth_md5"=>["auth_method = 'md5'", "host md5"],
    "host_auth_method_null"=>["'auth_method', NULL", "auth_method null"],
    "host_auth_error_present"=>["'error', 'parsed error'", "error regression"],
    "host_scram_false_positive"=>["bool_or(auth_method = 'scram-sha-256')", "false-positive"],
    "sqlstate_mismatch"=>["wrong sqlstate", "sqlstate_42501"],
    "cross_tenant_insert_allowed"=>["cross-tenant", "tenant_escape_denied"],
    "search_path_drift"=>["search_path", "fixed_search_path_true"],
    "observation_insert_missing"=>["DEFAULT VALUES", "seed exactly one observation row"],
    "tenant_observation_insert_allowed"=>["GRANT ALL ON atlas_query_security_observation", "must not allow tenant observation inserts"],
    "observation_update_zero_rows"=>["ROW_COUNT", "exact single-row observation updates"],
    "observation_final_zero_rows"=>["final cardinality expected 1 row", "exact final observation cardinality"],
    "observation_final_multiple_rows"=>["count(*) INTO observation_rows", "exact final observation cardinality"],
    "missing_json_result"=>["missing-json", "json_candidate_lines"],
    "marker_only_result"=>["marker-only", "marker_present"],
    "non_object_json_result"=>["non-object-json", "json_object_present"],
    "multiple_json_candidates"=>["multiple-json", "json_candidate_count_exactly_one"],
    "truncated_json_result"=>["truncated-json", "parse_error"]
  },
  "definitive-domain.query.sql-surface"=>{
    "current_user_policy_regression"=>["current_user", "policy_tenant"],
    "public_policy_regression"=>["PUBLIC", "public_policy_regression"],
    "other_tenant_insert_allowed"=>["other-tenant", "security_rejected"],
    "duplicate_key_not_rejected"=>["duplicate", "23505"],
    "check_violation_not_rejected"=>["check", "23514"],
    "do_semicolon_missing"=>["END;", "terminate every DO block"],
    "observation_insert_missing"=>["DEFAULT VALUES", "seed exactly one observation row"],
    "observation_duplicate_seed"=>["DEFAULT VALUES", "seed exactly one observation row"],
    "tenant_observation_insert_allowed"=>["GRANT ALL ON atlas_sql_surface_observation", "must not allow tenant observation inserts"],
    "observation_update_zero_rows"=>["ROW_COUNT", "atlas_sql_surface_observation"],
    "observation_final_zero_rows"=>["final cardinality expected 1 row", "final observation cardinality"],
    "observation_final_multiple_rows"=>["final cardinality expected 1 row", "final observation cardinality"],
    "generic_unknown_failure_mapping"=>["psql_json_execution_for_row!(", "row-specific structured command and JSON failure mapping"],
    "grant_update_regression"=>["UPDATE", "grant_update_regression"],
    "first_nested_begin_missing"=>["first nested BEGIN", "outer BEGIN must directly contain the first nested BEGIN"],
    "sibling_refusal_block_outside_outer_do"=>["outside the outer DO block", "sibling refusal/check blocks inside the outer DO block"],
    "same_statement_visibility_snapshot_regression"=>["same-statement visibility snapshot", "visible_rows in a statement after RETURNING update"]
  },
  "definitive-domain.query.types-constraints"=>{
    "current_user_policy_regression"=>["current_user", "policy_tenant"],
    "public_policy_regression"=>["PUBLIC", "public_policy_regression"],
    "other_tenant_insert_allowed"=>["cross-tenant", "security_rejected"],
    "invalid_domain_not_rejected"=>["invalid-domain", "23514"],
    "do_semicolon_missing"=>["END;", "terminate every DO block"],
    "observation_insert_missing"=>["DEFAULT VALUES", "seed exactly one observation row"],
    "observation_duplicate_seed"=>["DEFAULT VALUES", "seed exactly one observation row"],
    "tenant_observation_insert_allowed"=>["GRANT ALL ON atlas_typed_order_observation", "must not allow tenant observation inserts"],
    "observation_update_zero_rows"=>["ROW_COUNT", "atlas_typed_order_observation"],
    "observation_final_zero_rows"=>["final cardinality expected 1 row", "final observation cardinality"],
    "observation_final_multiple_rows"=>["final cardinality expected 1 row", "final observation cardinality"],
    "generic_unknown_failure_mapping"=>["psql_json_execution_for_row!(", "row-specific structured command and JSON failure mapping"],
    "generated_value_drift"=>["generated-value", "atlas-order"],
    "uuid_version_drift"=>["uuid", "uuid_v7_exact"],
    "first_nested_begin_missing"=>["first nested BEGIN", "outer BEGIN must directly contain the first nested BEGIN"],
    "sibling_refusal_block_outside_outer_do"=>["outside the outer DO block", "sibling refusal blocks inside the outer DO block"]
  }
}.freeze

SecurityNextTrancheRowContracts.contracts.each do |contract|
  pattern_id = contract.fetch("pattern_id")
  contents = TEST_PATHS.fetch(pattern_id).map { |path| File.read(File.join(ROOT, path)) }.join("\n")
  contract.fetch("negative_cases").each do |negative|
    tokens = TOKENS.fetch(pattern_id).fetch(negative)
    unless tokens.any? { |token| contents.include?(token) }
      abort "negative coverage missing for #{pattern_id}: #{negative}"
    end
  end
end

puts "Next security tranche negative coverageを検証しました: all row-contract negatives are represented in targeted light tests"
