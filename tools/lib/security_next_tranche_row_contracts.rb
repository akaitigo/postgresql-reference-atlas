# frozen_string_literal: true

require "json"
require "yaml"
require_relative "security_scenario_tranche"

module SecurityNextTrancheRowContracts
  ROOT = File.expand_path("../..", __dir__)
  COMMAND = "ruby tools/run-scenario-security-001.rb"
  CONTRACTS = [
    {
      "pattern_id"=>"definitive-domain.query.partitioning",
      "target_id"=>"query.partitioning",
      "claim_id"=>"query.partitioning",
      "proof_obligation_id"=>"query.partition-routing-pruning",
      "executor_id"=>"partitioning-security",
      "runtime_kind"=>"postgresql-18.6-container",
      "oracle_id"=>"partition-routing-pruning-and-partition-ddl-owner-boundary",
      "support_paths"=>[
        "claims/query.partitioning.claim.yaml",
        "labs/partitioning/verify.sql",
        "tools/lib/atomic_evidence_publisher.rb",
        "tools/lib/security_failure_diagnostics.rb",
        "tools/lib/security_json_output.rb",
        "tools/lib/security_scenario_oracles.rb",
        "tools/lib/security_next_tranche_row_contracts.rb",
        "tools/run-scenario-security-001.rb"
      ],
      "sql_fragments"=>[
        "CREATE ROLE atlas_partition_reader;",
        "CREATE TABLE atlas_partition_secure(",
        "PARTITION BY RANGE (occurred_on)",
        "CREATE TABLE atlas_partition_secure_2026q1 PARTITION OF atlas_partition_secure",
        "CREATE TABLE atlas_partition_secure_2026q2 PARTITION OF atlas_partition_secure",
        "CREATE TABLE atlas_partition_secure_default PARTITION OF atlas_partition_secure DEFAULT",
        "INSERT INTO atlas_partition_secure VALUES",
        "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT",
        "WHERE tenant = ''atlas_partition_reader'' AND occurred_on = DATE ''2026-02-01''",
        "ALTER TABLE atlas_partition_secure DETACH PARTITION atlas_partition_secure_2026q1",
        "ATLAS_SECURITY_PASS:query.partitioning"
      ],
      "forbidden_sql_fragments"=>[
        "enable_partition_pruning = off",
        "enable_seqscan",
        "ALTER SYSTEM",
        "TO PUBLIC",
        "current_user"
      ],
      "required_result_fields"=>%w[
        server_version observation_rows q1_rows q2_rows default_rows partition_pruning security_rejected
        oracle_marker plan verdict
      ],
      "required_oracle_predicates"=>%w[
        result_verdict_pass
        server_version_exact
        observation_rows_exact
        q1_rows_exact
        q2_rows_exact
        default_rows_exact
        partition_pruning_true
        security_rejected
        marker_exact
        plan_document_array
        plan_actual_rows_and_loops
        plan_buffers_observed
        plan_q1_partition_present
        plan_q2_partition_absent
        plan_default_partition_absent
      ],
      "negative_cases"=>%w[
        detach_partition_allowed
        partition_pruning_missing
        q1_partition_missing
        q2_partition_visible
        default_partition_visible
        do_semicolon_missing
        observation_duplicate_seed
        tenant_observation_insert_allowed
        observation_update_zero_rows
        observation_final_zero_rows
        observation_final_multiple_rows
        generic_unknown_failure_mapping
        forced_partition_guc_present
      ],
      "diagnostic_fields"=>%w[
        actual_result oracle_predicates plan_nodes bindings canonical_artifacts
      ]
    },
    {
      "pattern_id"=>"definitive-domain.query.security",
      "target_id"=>"query.security",
      "claim_id"=>"query.security",
      "proof_obligation_id"=>"query.rls-boundary",
      "executor_id"=>"query-security",
      "runtime_kind"=>"postgresql-18.6-container",
      "oracle_id"=>"force-rls-tenant-boundary-scram-and-search-path",
      "support_paths"=>[
        "claims/query.security.claim.yaml",
        "labs/security/verify.sql",
        "tools/lib/atomic_evidence_publisher.rb",
        "tools/lib/security_failure_diagnostics.rb",
        "tools/lib/security_json_output.rb",
        "tools/lib/security_scenario_oracles.rb",
        "tools/lib/security_next_tranche_row_contracts.rb",
        "tools/run-scenario-security-001.rb"
      ],
      "sql_fragments"=>[
        "CREATE EXTENSION dblink;",
        "CREATE ROLE tenant_app LOGIN PASSWORD 'tenant-atlas'",
        "ALTER TABLE tenant_record FORCE ROW LEVEL SECURITY;",
        "CREATE POLICY tenant_isolation ON tenant_record",
        "current_setting('app.tenant_id')::integer",
        "SECURITY DEFINER",
        "SET search_path = pg_catalog, public",
        "COMMIT;",
        "BEGIN;",
        "SELECT dblink_connect('tenant1', 'host=127.0.0.1 dbname=atlas user=tenant_app password=tenant-atlas options=-capp.tenant_id=1');",
        "dblink_connect('tenant1'",
        "dblink_exec('tenant1', $q$INSERT INTO tenant_record VALUES (2, 2, 'escape')$q$)",
        "ATLAS_SECURITY_PASS:query.security"
      ],
      "forbidden_sql_fragments"=>[
        "ALTER ROLE tenant_app BYPASSRLS",
        "SET row_security = off",
        "TO PUBLIC",
        "ALTER SYSTEM",
        "enable_seqscan",
        "dbname=postgres",
        "host=/var/run/postgresql",
        "host=/tmp"
      ],
      "required_result_fields"=>%w[
        server_version observation_rows visible_rows tenant_escape_denied sqlstate password_encryption
        scram_verifier host_rule_rows effective_host_rule host_scram_rule fixed_search_path security_rejected oracle_marker verdict
      ],
      "required_oracle_predicates"=>%w[
        result_verdict_pass
        server_version_exact
        observation_rows_exact
        visible_rows_exact
        security_rejected
        sqlstate_42501
        password_encryption_scram
        scram_verifier_true
        host_scram_rule_true
        host_rule_rows_present
        effective_host_rule_present
        effective_host_rule_auth_method_scram
        effective_host_rule_error_blank
        fixed_search_path_true
        marker_exact
      ],
      "negative_cases"=>%w[
        force_rls_missing
        with_check_missing
        bypassrls_regression
        precommit_dblink_visibility
        missing_host_target
        wrong_db_target
        wrong_dblink_password
        wrong_socket_target
        initdb_auth_args_missing
        localhost_trust_precedes
        host_scram_append_only
        host_auth_rule_order_reversed
        host_auth_trust
        host_auth_md5
        host_auth_method_null
        host_auth_error_present
        host_scram_false_positive
        sqlstate_mismatch
        cross_tenant_insert_allowed
        search_path_drift
        observation_insert_missing
        tenant_observation_insert_allowed
        observation_update_zero_rows
        observation_final_zero_rows
        observation_final_multiple_rows
        missing_json_result
        marker_only_result
        non_object_json_result
        multiple_json_candidates
        truncated_json_result
      ],
      "diagnostic_fields"=>%w[
        actual_result oracle_predicates plan_nodes bindings canonical_artifacts
      ]
    },
    {
      "pattern_id"=>"definitive-domain.query.sql-surface",
      "target_id"=>"query.sql-surface",
      "claim_id"=>"query.sql-surface",
      "proof_obligation_id"=>"query.constraints-and-returning",
      "executor_id"=>"sql-surface-security",
      "runtime_kind"=>"postgresql-18.6-container",
      "oracle_id"=>"returning-and-constraint-rejections-with-tenant-scoped-write-boundary",
      "support_paths"=>[
        "claims/query.sql-surface.claim.yaml",
        "labs/sql-surface/run.sh",
        "tools/verify-sql-surface.rb",
        "tools/lib/atomic_evidence_publisher.rb",
        "tools/lib/security_failure_diagnostics.rb",
        "tools/lib/security_json_output.rb",
        "tools/lib/security_scenario_oracles.rb",
        "tools/lib/security_next_tranche_row_contracts.rb",
        "tools/run-scenario-security-001.rb"
      ],
      "sql_fragments"=>[
        "CREATE ROLE atlas_sql_surface_writer LOGIN PASSWORD 'atlas-sql-surface';",
        "CREATE TABLE atlas_sql_surface_secure(",
        "PRIMARY KEY (tenant, id)",
        "CHECK (amount > 0)",
        "ALTER TABLE atlas_sql_surface_secure ENABLE ROW LEVEL SECURITY;",
        "CREATE POLICY atlas_sql_surface_policy ON atlas_sql_surface_secure",
        "TO atlas_sql_surface_writer",
        "USING (tenant = 'atlas_sql_surface_writer')",
        "WITH CHECK (tenant = 'atlas_sql_surface_writer')",
        "GRANT SELECT, INSERT ON atlas_sql_surface_secure TO atlas_sql_surface_writer;",
        "RETURNING id, note",
        "ATLAS_SECURITY_PASS:query.sql-surface"
      ],
      "forbidden_sql_fragments"=>[
        "current_user",
        "TO PUBLIC",
        "GRANT UPDATE",
        "ALTER SYSTEM",
        "enable_seqscan"
      ],
      "required_result_fields"=>%w[
        server_version observation_rows returned_id returned_note visible_rows duplicate_key_sqlstate
        check_violation_sqlstate security_rejected oracle_marker verdict
      ],
      "required_oracle_predicates"=>%w[
        result_verdict_pass
        server_version_exact
        observation_rows_exact
        returned_id_exact
        returned_note_exact
        visible_rows_exact
        duplicate_key_sqlstate_exact
        check_violation_sqlstate_exact
        security_rejected
        marker_exact
        literal_tenant_policy_exact
      ],
      "negative_cases"=>%w[
        current_user_policy_regression
        public_policy_regression
        other_tenant_insert_allowed
        duplicate_key_not_rejected
        check_violation_not_rejected
        do_semicolon_missing
        observation_insert_missing
        observation_duplicate_seed
        tenant_observation_insert_allowed
        observation_update_zero_rows
        observation_final_zero_rows
        observation_final_multiple_rows
        generic_unknown_failure_mapping
        grant_update_regression
        first_nested_begin_missing
        sibling_refusal_block_outside_outer_do
        same_statement_visibility_snapshot_regression
      ],
      "diagnostic_fields"=>%w[
        actual_result oracle_predicates plan_nodes bindings canonical_artifacts
      ]
    },
    {
      "pattern_id"=>"definitive-domain.query.types-constraints",
      "target_id"=>"query.types-constraints",
      "claim_id"=>"query.types-constraints",
      "proof_obligation_id"=>"query.types-constraints",
      "executor_id"=>"types-constraints-security",
      "runtime_kind"=>"postgresql-18.6-container",
      "oracle_id"=>"typed-roundtrip-domain-rejection-with-tenant-scoped-write-boundary",
      "support_paths"=>[
        "claims/query.types-constraints.claim.yaml",
        "labs/types-constraints/verify.sql",
        "tools/lib/atomic_evidence_publisher.rb",
        "tools/lib/security_failure_diagnostics.rb",
        "tools/lib/security_json_output.rb",
        "tools/lib/security_scenario_oracles.rb",
        "tools/lib/security_next_tranche_row_contracts.rb",
        "tools/run-scenario-security-001.rb"
      ],
      "sql_fragments"=>[
        "CREATE ROLE atlas_typed_order_writer LOGIN PASSWORD 'atlas-types';",
        "CREATE DOMAIN positive_money AS numeric(12,2) CHECK (VALUE > 0);",
        "CREATE TYPE order_status AS ENUM ('draft', 'confirmed', 'cancelled');",
        "CREATE TABLE atlas_typed_order_secure(",
        "DEFAULT uuidv7()",
        "GENERATED ALWAYS AS (metadata ->> 'name') STORED",
        "ALTER TABLE atlas_typed_order_secure ENABLE ROW LEVEL SECURITY;",
        "CREATE POLICY atlas_typed_order_policy ON atlas_typed_order_secure",
        "TO atlas_typed_order_writer",
        "USING (tenant = 'atlas_typed_order_writer')",
        "WITH CHECK (tenant = 'atlas_typed_order_writer')",
        "ATLAS_SECURITY_PASS:query.types-constraints"
      ],
      "forbidden_sql_fragments"=>[
        "current_user",
        "TO PUBLIC",
        "ALTER SYSTEM",
        "enable_seqscan",
        "ALTER ROLE atlas_typed_order_writer BYPASSRLS"
      ],
      "required_result_fields"=>%w[
        server_version observation_rows row_count uuid_version array_contains json_path range_contains
        generated_value invalid_domain_sqlstate security_rejected oracle_marker verdict
      ],
      "required_oracle_predicates"=>%w[
        result_verdict_pass
        server_version_exact
        observation_rows_exact
        row_count_exact
        uuid_v7_exact
        array_contains_true
        json_path_true
        range_contains_true
        generated_value_exact
        invalid_domain_sqlstate_exact
        security_rejected
        marker_exact
        literal_tenant_policy_exact
      ],
      "negative_cases"=>%w[
        current_user_policy_regression
        public_policy_regression
        other_tenant_insert_allowed
        invalid_domain_not_rejected
        do_semicolon_missing
        observation_insert_missing
        observation_duplicate_seed
        tenant_observation_insert_allowed
        observation_update_zero_rows
        observation_final_zero_rows
        observation_final_multiple_rows
        generic_unknown_failure_mapping
        generated_value_drift
        uuid_version_drift
        first_nested_begin_missing
        sibling_refusal_block_outside_outer_do
      ],
      "diagnostic_fields"=>%w[
        actual_result oracle_predicates plan_nodes bindings canonical_artifacts
      ]
    }
  ].freeze

  module_function

  def contracts
    JSON.parse(JSON.generate(CONTRACTS))
  end

  def row_ids(items = contracts)
    items.map { |row| SecurityScenarioTranche.row_id_for(row.fetch("pattern_id")) }
  end

  def verify!(candidate_contracts = contracts)
    raise "next tranche row contract cardinality drifted" unless candidate_contracts.length == SecurityScenarioTranche::LATEST_RUNTIME_TRANCHE_PATTERN_IDS.length
    raise "next tranche row contract pattern order drifted" unless candidate_contracts.map { |row| row.fetch("pattern_id") } == SecurityScenarioTranche::LATEST_RUNTIME_TRANCHE_PATTERN_IDS
    raise "next tranche row contract row_ids drifted" unless row_ids(candidate_contracts) == SecurityScenarioTranche.expected_latest_runtime_row_ids

    expected_by_pattern = CONTRACTS.to_h { |row| [row.fetch("pattern_id"), row] }
    candidate_contracts.each do |row|
      verify_contract_row!(row, expected_by_pattern.fetch(row.fetch("pattern_id")))
    end
    true
  end

  def verify_contract_row!(row, expected_row)
    required_keys = %w[
      pattern_id target_id claim_id proof_obligation_id executor_id runtime_kind oracle_id
      support_paths sql_fragments forbidden_sql_fragments required_result_fields
      required_oracle_predicates negative_cases diagnostic_fields
    ]
    missing = required_keys.reject { |key| row.key?(key) }
    raise "next tranche row contract missing keys: #{missing.join(', ')}" unless missing.empty?

    raise "next tranche row contract target drifted for #{row.fetch('pattern_id')}" unless row.fetch("target_id") == row.fetch("pattern_id").delete_prefix("definitive-domain.")
    %w[claim_id proof_obligation_id executor_id runtime_kind oracle_id].each do |field|
      raise "next tranche row contract #{field} drifted for #{row.fetch('pattern_id')}" unless row.fetch(field) == expected_row.fetch(field)
    end
    %w[support_paths sql_fragments forbidden_sql_fragments required_result_fields required_oracle_predicates negative_cases diagnostic_fields].each do |field|
      raise "next tranche row contract #{field} drifted for #{row.fetch('pattern_id')}" unless row.fetch(field) == expected_row.fetch(field)
    end

    raise "next tranche row contract support paths empty for #{row.fetch('pattern_id')}" if row.fetch("support_paths").empty?
    raise "next tranche row contract sql fragments weakened for #{row.fetch('pattern_id')}" unless row.fetch("sql_fragments").length >= 10
    raise "next tranche row contract negatives weakened for #{row.fetch('pattern_id')}" unless row.fetch("negative_cases").length >= 6
    raise "next tranche row contract diagnostic fields weakened for #{row.fetch('pattern_id')}" unless row.fetch("diagnostic_fields").length >= 5
    raise "next tranche row contract contains duplicate sql fragments for #{row.fetch('pattern_id')}" unless row.fetch("sql_fragments").uniq == row.fetch("sql_fragments")
    raise "next tranche row contract contains duplicate negatives for #{row.fetch('pattern_id')}" unless row.fetch("negative_cases").uniq == row.fetch("negative_cases")

    missing_paths = row.fetch("support_paths").reject { |path| File.file?(File.join(ROOT, path)) }
    raise "next tranche row contract support path missing for #{row.fetch('pattern_id')}: #{missing_paths.join(', ')}" unless missing_paths.empty?

    claim = YAML.safe_load(File.read(File.join(ROOT, "claims/#{row.fetch('claim_id')}.claim.yaml")), aliases: false)
    raise "next tranche row contract claim id drifted for #{row.fetch('pattern_id')}" unless claim.fetch("id") == row.fetch("claim_id")
    proof_ids = Array(claim.fetch("proof_obligations")).map { |item| item.fetch("id") }
    raise "next tranche row contract proof obligation drifted for #{row.fetch('pattern_id')}" unless proof_ids.include?(row.fetch("proof_obligation_id"))
  end
end
