# frozen_string_literal: true

require "json"

module SecurityQueryCatalogInventoryContract
  CONTRACT = {
    "pattern_id"=>"definitive-domain.query.catalog-inventory",
    "target_id"=>"query.catalog-inventory",
    "executor_id"=>"catalog-inventory-security",
    "command"=>"ruby tools/run-scenario-security-001.rb",
    "runtime_kind"=>"postgresql-18.6-container",
    "sql_fragments"=>[
      "CREATE ROLE atlas_catalog_reader;",
      "SELECT count(*) AS count, md5(string_agg(oid::text || ':' || typname",
      "FROM pg_type WHERE typnamespace = 'pg_catalog'::regnamespace",
      "FROM pg_proc WHERE pronamespace = 'pg_catalog'::regnamespace",
      "FROM pg_operator WHERE oprnamespace = 'pg_catalog'::regnamespace",
      "FROM pg_cast",
      "FROM pg_am",
      "FROM pg_collation",
      "FROM pg_available_extensions",
      "FROM pg_class c WHERE c.relnamespace = 'pg_catalog'::regnamespace",
      "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT oid, typname FROM pg_type WHERE typnamespace = 'pg_catalog'::regnamespace ORDER BY oid LIMIT 10",
      "CREATE TABLE pg_catalog.atlas_catalog_forged",
      "ATLAS_SECURITY_PASS:query.catalog-inventory"
    ],
    "forbidden_sql_fragments"=>[
      "enable_seqscan",
      "enable_indexscan",
      "enable_bitmapscan",
      "ALTER SYSTEM",
      "DROP TABLE pg_catalog",
      "CREATE EXTENSION"
    ],
    "required_result_fields"=>%w[
      server_version types functions operators casts access_methods collations
      available_extensions catalog_relations security_rejected oracle_marker plan verdict
    ],
    "required_oracle_predicates"=>%w[
      result_verdict_pass
      server_version_exact
      types_count_threshold
      functions_count_threshold
      operators_count_threshold
      casts_count_threshold
      access_methods_threshold
      collations_count_positive
      available_extensions_threshold
      catalog_relations_threshold
      digests_present
      security_rejected
      marker_exact
      plan_document_array
      plan_actual_rows_and_loops
      plan_buffers_observed
      plan_reads_pg_catalog_type_relation
    ],
    "negative_cases"=>%w[
      catalog_digest_missing
      count_only_self_report
      non_pg_catalog_scope
      unordered_digest_capture
      unauthorized_catalog_mutation_allowed
      forced_planner_guc_present
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
    raise "query.catalog-inventory contract pattern drifted" unless candidate.fetch("pattern_id") == CONTRACT.fetch("pattern_id")
    raise "query.catalog-inventory contract target drifted" unless candidate.fetch("target_id") == CONTRACT.fetch("target_id")
    raise "query.catalog-inventory contract executor drifted" unless candidate.fetch("executor_id") == CONTRACT.fetch("executor_id")
    raise "query.catalog-inventory contract command drifted" unless candidate.fetch("command") == CONTRACT.fetch("command")
    raise "query.catalog-inventory contract runtime drifted" unless candidate.fetch("runtime_kind") == CONTRACT.fetch("runtime_kind")
    raise "query.catalog-inventory contract sql fragments drifted" unless candidate.fetch("sql_fragments") == CONTRACT.fetch("sql_fragments")
    raise "query.catalog-inventory contract forbidden sql drifted" unless candidate.fetch("forbidden_sql_fragments") == CONTRACT.fetch("forbidden_sql_fragments")
    raise "query.catalog-inventory contract result fields drifted" unless candidate.fetch("required_result_fields") == CONTRACT.fetch("required_result_fields")
    raise "query.catalog-inventory contract oracle predicates drifted" unless candidate.fetch("required_oracle_predicates") == CONTRACT.fetch("required_oracle_predicates")
    raise "query.catalog-inventory contract negatives drifted" unless candidate.fetch("negative_cases") == CONTRACT.fetch("negative_cases")
    raise "query.catalog-inventory contract diagnostic fields drifted" unless candidate.fetch("diagnostic_fields") == CONTRACT.fetch("diagnostic_fields")

    raise "query.catalog-inventory contract sql fragments weakened" unless candidate.fetch("sql_fragments").length >= 12
    raise "query.catalog-inventory contract negatives weakened" unless candidate.fetch("negative_cases").length >= 6
    raise "query.catalog-inventory contract diagnostic fields weakened" unless candidate.fetch("diagnostic_fields").length >= 5
    raise "query.catalog-inventory contract contains duplicate sql fragments" unless candidate.fetch("sql_fragments").uniq == candidate.fetch("sql_fragments")
    raise "query.catalog-inventory contract contains duplicate negatives" unless candidate.fetch("negative_cases").uniq == candidate.fetch("negative_cases")
    true
  end
end
