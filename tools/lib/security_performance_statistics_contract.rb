# frozen_string_literal: true

require "json"

module SecurityPerformanceStatisticsContract
  CONTRACT = {
    "pattern_id"=>"definitive-domain.performance.statistics",
    "target_id"=>"performance.statistics",
    "executor_id"=>"performance-statistics-security",
    "command"=>"ruby tools/run-scenario-security-001.rb",
    "runtime_kind"=>"postgresql-18.6-container",
    "sql_fragments"=>[
      "CREATE ROLE atlas_perf_statistics_reader;",
      "CREATE TABLE correlated_fact(a integer NOT NULL, b integer NOT NULL, payload text NOT NULL);",
      "GRANT SELECT ON correlated_fact TO atlas_perf_statistics_reader;",
      "CREATE STATISTICS correlated_fact_ab (dependencies, mcv) ON a, b FROM correlated_fact;",
      "ANALYZE correlated_fact;",
      "SET ROLE atlas_perf_statistics_reader;",
      "EXPLAIN (FORMAT JSON) SELECT * FROM correlated_fact WHERE a = 42 AND b = 42",
      "CREATE STATISTICS atlas_perf_statistics_reader_attempt",
      "ANALYZE correlated_fact",
      "ATLAS_SECURITY_PASS:performance.statistics"
    ],
    "forbidden_sql_fragments"=>[
      "enable_seqscan",
      "enable_bitmapscan",
      "enable_indexscan",
      "ALTER SYSTEM",
      "SET LOCAL enable_seqscan",
      "current_user"
    ],
    "required_result_fields"=>%w[
      server_version statistics_kinds estimated_rows actual_rows security_rejected oracle_marker plan verdict
    ],
    "required_oracle_predicates"=>%w[
      result_verdict_pass
      server_version_exact
      statistics_kinds_exact
      estimated_rows_window
      actual_rows_exact
      security_rejected
      marker_exact
      plan_document_array
      plan_rows_match_estimate
    ],
    "negative_cases"=>%w[
      estimated_rows_outside_80_120
      actual_rows_not_100
      missing_dependencies_or_mcv_statistics
      unauthorized_create_statistics_allowed
      unauthorized_analyze_allowed
      forced_planner_guc_present
      boolean_spoof_without_plan
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
    raise "performance.statistics contract pattern drifted" unless candidate.fetch("pattern_id") == CONTRACT.fetch("pattern_id")
    raise "performance.statistics contract target drifted" unless candidate.fetch("target_id") == CONTRACT.fetch("target_id")
    raise "performance.statistics contract executor drifted" unless candidate.fetch("executor_id") == CONTRACT.fetch("executor_id")
    raise "performance.statistics contract command drifted" unless candidate.fetch("command") == CONTRACT.fetch("command")
    raise "performance.statistics contract runtime drifted" unless candidate.fetch("runtime_kind") == CONTRACT.fetch("runtime_kind")
    raise "performance.statistics contract sql fragments drifted" unless candidate.fetch("sql_fragments") == CONTRACT.fetch("sql_fragments")
    raise "performance.statistics contract forbidden sql drifted" unless candidate.fetch("forbidden_sql_fragments") == CONTRACT.fetch("forbidden_sql_fragments")
    raise "performance.statistics contract result fields drifted" unless candidate.fetch("required_result_fields") == CONTRACT.fetch("required_result_fields")
    raise "performance.statistics contract oracle predicates drifted" unless candidate.fetch("required_oracle_predicates") == CONTRACT.fetch("required_oracle_predicates")
    raise "performance.statistics contract negatives drifted" unless candidate.fetch("negative_cases") == CONTRACT.fetch("negative_cases")
    raise "performance.statistics contract diagnostic fields drifted" unless candidate.fetch("diagnostic_fields") == CONTRACT.fetch("diagnostic_fields")

    raise "performance.statistics contract sql fragments weakened" unless candidate.fetch("sql_fragments").length >= 10
    raise "performance.statistics contract negatives weakened" unless candidate.fetch("negative_cases").length >= 6
    raise "performance.statistics contract diagnostic fields weakened" unless candidate.fetch("diagnostic_fields").length >= 5
    raise "performance.statistics contract contains duplicate sql fragments" unless candidate.fetch("sql_fragments").uniq == candidate.fetch("sql_fragments")
    raise "performance.statistics contract contains duplicate negatives" unless candidate.fetch("negative_cases").uniq == candidate.fetch("negative_cases")
    true
  end
end
