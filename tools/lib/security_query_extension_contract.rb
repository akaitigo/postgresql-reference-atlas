# frozen_string_literal: true

require "json"

module SecurityQueryExtensionContract
  CONTRACT = {
    "pattern_id"=>"definitive-domain.query.extension",
    "target_id"=>"query.extension",
    "executor_id"=>"bundled-extension-security",
    "command"=>"ruby tools/run-scenario-security-001.rb",
    "runtime_kind"=>"postgresql-18.6-container",
    "sql_fragments"=>[
      "CREATE ROLE atlas_extension_reader;",
      "CREATE EXTENSION pg_trgm;",
      "CREATE TABLE atlas_extension_secure(",
      "ALTER TABLE atlas_extension_secure ENABLE ROW LEVEL SECURITY;",
      "CREATE POLICY atlas_extension_policy ON atlas_extension_secure",
      "TO atlas_extension_reader",
      "USING (tenant = 'atlas_extension_reader' AND body LIKE '%searchable phrase%')",
      "WITH CHECK (tenant = 'atlas_extension_reader')",
      "CREATE INDEX atlas_extension_secure_body_trgm_idx ON atlas_extension_secure USING gin (body gin_trgm_ops);",
      "ANALYZE atlas_extension_secure;",
      "EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) SELECT id FROM atlas_extension_secure WHERE tenant = ''atlas_extension_reader'' AND body LIKE ''%searchable phrase%'' ORDER BY id",
      "CREATE EXTENSION hstore;",
      "ATLAS_SECURITY_PASS:query.extension"
    ],
    "forbidden_sql_fragments"=>[
      "enable_seqscan",
      "enable_indexscan",
      "enable_bitmapscan",
      "ALTER SYSTEM",
      "current_user",
      "TO PUBLIC"
    ],
    "required_result_fields"=>%w[
      server_version extension_version similarity matching_rows security_rejected
      oracle_marker plan verdict
    ],
    "required_oracle_predicates"=>%w[
      result_verdict_pass
      server_version_exact
      extension_version_present
      similarity_positive
      matching_rows_exact
      security_rejected
      marker_exact
      plan_document_array
      plan_actual_rows_and_loops
      plan_buffers_observed
      plan_exact_gin_index
      plan_exact_relation
      plan_literal_tenant_observed
      plan_seq_scan_absent_on_exact_relation
    ],
    "negative_cases"=>%w[
      pg_trgm_missing
      gin_index_missing
      matching_rows_not_one
      wrong_index_name
      unauthorized_extension_install_allowed
      forced_planner_guc_present
      current_user_policy_regression
      public_policy_regression
    ],
    "diagnostic_fields"=>%w[
      actual_result oracle_predicates plan_nodes bindings canonical_artifacts
    ]
  }.freeze

  module_function

  def contract
    JSON.parse(JSON.generate(CONTRACT))
  end

  def verify!(candidate = contract)
    raise "query.extension contract pattern drifted" unless candidate.fetch("pattern_id") == CONTRACT.fetch("pattern_id")
    raise "query.extension contract target drifted" unless candidate.fetch("target_id") == CONTRACT.fetch("target_id")
    raise "query.extension contract executor drifted" unless candidate.fetch("executor_id") == CONTRACT.fetch("executor_id")
    raise "query.extension contract command drifted" unless candidate.fetch("command") == CONTRACT.fetch("command")
    raise "query.extension contract runtime drifted" unless candidate.fetch("runtime_kind") == CONTRACT.fetch("runtime_kind")
    raise "query.extension contract sql fragments drifted" unless candidate.fetch("sql_fragments") == CONTRACT.fetch("sql_fragments")
    raise "query.extension contract forbidden sql drifted" unless candidate.fetch("forbidden_sql_fragments") == CONTRACT.fetch("forbidden_sql_fragments")
    raise "query.extension contract result fields drifted" unless candidate.fetch("required_result_fields") == CONTRACT.fetch("required_result_fields")
    raise "query.extension contract oracle predicates drifted" unless candidate.fetch("required_oracle_predicates") == CONTRACT.fetch("required_oracle_predicates")
    raise "query.extension contract negatives drifted" unless candidate.fetch("negative_cases") == CONTRACT.fetch("negative_cases")
    raise "query.extension contract diagnostic fields drifted" unless candidate.fetch("diagnostic_fields") == CONTRACT.fetch("diagnostic_fields")

    raise "query.extension contract sql fragments weakened" unless candidate.fetch("sql_fragments").length >= 12
    raise "query.extension contract negatives weakened" unless candidate.fetch("negative_cases").length >= 6
    raise "query.extension contract diagnostic fields weakened" unless candidate.fetch("diagnostic_fields").length >= 5
    raise "query.extension contract contains duplicate sql fragments" unless candidate.fetch("sql_fragments").uniq == candidate.fetch("sql_fragments")
    raise "query.extension contract contains duplicate negatives" unless candidate.fetch("negative_cases").uniq == candidate.fetch("negative_cases")
    true
  end
end
