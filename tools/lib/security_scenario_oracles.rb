# frozen_string_literal: true

module SecurityScenarioOracles
  PERFORMANCE_EXECUTION_RELATION = "atlas_perf_execution_secure"
  PERFORMANCE_EXECUTION_INDEX = "atlas_perf_execution_tenant_idx"
  PERFORMANCE_INDEX_RELATION = "atlas_perf_index_secure"
  PERFORMANCE_INDEX_INDEX = "atlas_perf_index_billed_idx"
  PERFORMANCE_INDEX_LITERAL_TENANT = "atlas_perf_index_reader"
  PERFORMANCE_PLANNER_RELATION = "atlas_perf_planner_secure"
  PERFORMANCE_PLANNER_INDEX = "atlas_perf_planner_secure_pkey"
  INDEX_SCAN_NODE_TYPES = ["Index Scan", "Index Only Scan", "Bitmap Index Scan"].freeze
  BUFFER_KEYS = [
    "Shared Hit Blocks", "Shared Read Blocks", "Shared Dirtied Blocks", "Shared Written Blocks",
    "Local Hit Blocks", "Local Read Blocks", "Local Dirtied Blocks", "Local Written Blocks",
    "Temp Read Blocks", "Temp Written Blocks"
  ].freeze

  module_function

  def performance_execution_predicates(result, marker:)
    nodes = plan_document_nodes(result["plan"])
    {
      "result_verdict_pass"=>result.fetch("verdict") == "pass",
      "server_version_exact"=>result.fetch("server_version") == "18.6",
      "fixture_rows_exact"=>result.fetch("fixture_rows") == 200_000,
      "visible_rows_exact"=>result.fetch("visible_rows") == 200,
      "security_rejected"=>result.fetch("security_rejected") == true,
      "marker_exact"=>result.fetch("oracle_marker") == marker,
      "index_bytes_positive"=>result.fetch("index_bytes").to_i.positive?,
      "heap_bytes_positive"=>result.fetch("heap_bytes").to_i.positive?,
      "plan_document_array"=>result.fetch("plan").is_a?(Array) && !result.fetch("plan").empty?,
      "plan_exact_index_path"=>exact_index_path?(nodes: nodes, relation: PERFORMANCE_EXECUTION_RELATION, index: PERFORMANCE_EXECUTION_INDEX),
      "plan_actual_rows_and_loops"=>plan_has_actual_execution?(nodes),
      "plan_buffers_observed"=>plan_has_buffers?(nodes),
      "plan_seq_scan_absent_on_exact_relation"=>seq_scan_absent_on_relation?(nodes: nodes, relation: PERFORMANCE_EXECUTION_RELATION)
    }
  end

  def performance_execution_pass?(result, marker:)
    performance_execution_predicates(result, marker: marker).values.all?
  end

  def performance_execution_plan_valid?(plan_document)
    nodes = plan_document_nodes(plan_document)
    plan_has_actual_execution?(nodes) &&
      plan_has_buffers?(nodes) &&
      exact_index_path?(nodes: nodes, relation: PERFORMANCE_EXECUTION_RELATION, index: PERFORMANCE_EXECUTION_INDEX) &&
      seq_scan_absent_on_relation?(nodes: nodes, relation: PERFORMANCE_EXECUTION_RELATION)
  end

  def performance_index_predicates(result, marker:)
    nodes = plan_document_nodes(result["plan"])
    expected_billed_rows = result.fetch("billed_visible_rows")
    {
      "result_verdict_pass"=>result.fetch("verdict") == "pass",
      "server_version_exact"=>result.fetch("server_version") == "18.6",
      "before_after_digest_equal"=>result.fetch("before_digest") == result.fetch("after_digest"),
      "before_digest_present"=>!result.fetch("before_digest").to_s.empty?,
      "tenant_rows_exact"=>result.fetch("tenant_rows") == 200,
      "billed_visible_rows_exact"=>expected_billed_rows == 100,
      "security_rejected"=>result.fetch("security_rejected") == true,
      "marker_exact"=>result.fetch("oracle_marker") == marker,
      "index_bytes_positive"=>result.fetch("index_bytes").to_i.positive?,
      "heap_bytes_positive"=>result.fetch("heap_bytes").to_i.positive?,
      "partial_index_predicate_exact"=>result.fetch("index_predicate") == "billed",
      "plan_document_array"=>result.fetch("plan").is_a?(Array) && !result.fetch("plan").empty?,
      "plan_exact_index_path"=>exact_index_path?(nodes: nodes, relation: PERFORMANCE_INDEX_RELATION, index: PERFORMANCE_INDEX_INDEX),
      "plan_actual_rows_and_loops"=>plan_has_actual_execution?(nodes),
      "plan_actual_rows_match_billed_visible_rows"=>plan_has_exact_actual_rows?(nodes: nodes, expected: expected_billed_rows),
      "plan_buffers_observed"=>plan_has_buffers?(nodes),
      "plan_literal_tenant_observed"=>condition_includes?(nodes: nodes, expected: PERFORMANCE_INDEX_LITERAL_TENANT),
      "plan_seq_scan_absent_on_exact_relation"=>seq_scan_absent_on_relation?(nodes: nodes, relation: PERFORMANCE_INDEX_RELATION)
    }
  end

  def performance_index_pass?(result, marker:)
    performance_index_predicates(result, marker: marker).values.all?
  end

  def performance_planner_predicates(result, marker:)
    nodes = plan_document_nodes(result["plan"])
    {
      "result_verdict_pass"=>result.fetch("verdict") == "pass",
      "server_version_exact"=>result.fetch("server_version") == "18.6",
      "fixture_rows_exact"=>result.fetch("fixture_rows") == 100_000,
      "visible_rows_exact"=>result.fetch("visible_rows") == 1,
      "security_rejected"=>result.fetch("security_rejected") == true,
      "marker_exact"=>result.fetch("oracle_marker") == marker,
      "plan_document_array"=>result.fetch("plan").is_a?(Array) && !result.fetch("plan").empty?,
      "plan_exact_index_path"=>exact_index_path?(nodes: nodes, relation: PERFORMANCE_PLANNER_RELATION, index: PERFORMANCE_PLANNER_INDEX),
      "plan_actual_rows_and_loops"=>plan_has_actual_execution?(nodes),
      "plan_buffers_observed"=>plan_has_buffers?(nodes),
      "plan_seq_scan_absent_on_exact_relation"=>seq_scan_absent_on_relation?(nodes: nodes, relation: PERFORMANCE_PLANNER_RELATION)
    }
  end

  def performance_planner_pass?(result, marker:)
    performance_planner_predicates(result, marker: marker).values.all?
  end

  def query_partitioning_predicates(result, marker:)
    nodes = plan_document_nodes(result["plan"])
    {
      "result_verdict_pass"=>result.fetch("verdict") == "pass",
      "server_version_exact"=>result.fetch("server_version") == "18.6",
      "observation_rows_exact"=>result.fetch("observation_rows") == 1,
      "q1_rows_exact"=>result.fetch("q1_rows") == 1,
      "q2_rows_exact"=>result.fetch("q2_rows") == 1,
      "default_rows_exact"=>result.fetch("default_rows") == 1,
      "partition_pruning_true"=>result.fetch("partition_pruning") == true,
      "security_rejected"=>result.fetch("security_rejected") == true,
      "marker_exact"=>result.fetch("oracle_marker") == marker,
      "plan_document_array"=>result.fetch("plan").is_a?(Array) && !result.fetch("plan").empty?,
      "plan_actual_rows_and_loops"=>plan_has_actual_execution?(nodes),
      "plan_buffers_observed"=>plan_has_buffers?(nodes),
      "plan_q1_partition_present"=>nodes.any? { |node| node["Relation Name"] == "atlas_partition_secure_2026q1" },
      "plan_q2_partition_absent"=>nodes.none? { |node| node["Relation Name"] == "atlas_partition_secure_2026q2" },
      "plan_default_partition_absent"=>nodes.none? { |node| node["Relation Name"] == "atlas_partition_secure_default" }
    }
  end

  def query_partitioning_pass?(result, marker:)
    query_partitioning_predicates(result, marker: marker).values.all?
  end

  def query_security_predicates(result, marker:)
    effective_host_rule = result.fetch("effective_host_rule")
    host_rule_rows = result.fetch("host_rule_rows")
    {
      "result_verdict_pass"=>result.fetch("verdict") == "pass",
      "server_version_exact"=>result.fetch("server_version") == "18.6",
      "observation_rows_exact"=>result.fetch("observation_rows") == 1,
      "visible_rows_exact"=>result.fetch("visible_rows") == 1,
      "security_rejected"=>result.fetch("tenant_escape_denied") == true,
      "sqlstate_42501"=>result.fetch("sqlstate") == "42501",
      "password_encryption_scram"=>result.fetch("password_encryption") == "scram-sha-256",
      "scram_verifier_true"=>result.fetch("scram_verifier") == true,
      "host_scram_rule_true"=>result.fetch("host_scram_rule") == true,
      "host_rule_rows_present"=>host_rule_rows.is_a?(Array) && !host_rule_rows.empty?,
      "effective_host_rule_present"=>effective_host_rule.is_a?(Hash) && effective_host_rule["line_number"].is_a?(Numeric),
      "effective_host_rule_auth_method_scram"=>effective_host_rule.is_a?(Hash) && effective_host_rule["auth_method"] == "scram-sha-256",
      "effective_host_rule_error_blank"=>effective_host_rule.is_a?(Hash) && [nil, ""].include?(effective_host_rule["error"]),
      "fixed_search_path_true"=>result.fetch("fixed_search_path") == true,
      "marker_exact"=>result.fetch("oracle_marker") == marker
    }
  end

  def query_security_pass?(result, marker:)
    query_security_predicates(result, marker: marker).values.all?
  end

  def query_sql_surface_predicates(result, marker:)
    {
      "result_verdict_pass"=>result.fetch("verdict") == "pass",
      "server_version_exact"=>result.fetch("server_version") == "18.6",
      "observation_rows_exact"=>result.fetch("observation_rows") == 1,
      "returned_id_exact"=>result.fetch("returned_id") == 1,
      "returned_note_exact"=>result.fetch("returned_note") == "created",
      "visible_rows_exact"=>result.fetch("visible_rows") == 1,
      "duplicate_key_sqlstate_exact"=>result.fetch("duplicate_key_sqlstate") == "23505",
      "check_violation_sqlstate_exact"=>result.fetch("check_violation_sqlstate") == "23514",
      "security_rejected"=>result.fetch("security_rejected") == true,
      "marker_exact"=>result.fetch("oracle_marker") == marker,
      "literal_tenant_policy_exact"=>result.fetch("policy_tenant") == "atlas_sql_surface_writer"
    }
  end

  def query_sql_surface_pass?(result, marker:)
    query_sql_surface_predicates(result, marker: marker).values.all?
  end

  def query_types_constraints_predicates(result, marker:)
    {
      "result_verdict_pass"=>result.fetch("verdict") == "pass",
      "server_version_exact"=>result.fetch("server_version") == "18.6",
      "observation_rows_exact"=>result.fetch("observation_rows") == 1,
      "row_count_exact"=>result.fetch("row_count") == 1,
      "uuid_v7_exact"=>result.fetch("uuid_version") == 7,
      "array_contains_true"=>result.fetch("array_contains") == true,
      "json_path_true"=>result.fetch("json_path") == true,
      "range_contains_true"=>result.fetch("range_contains") == true,
      "generated_value_exact"=>result.fetch("generated_value") == "atlas-order",
      "invalid_domain_sqlstate_exact"=>result.fetch("invalid_domain_sqlstate") == "23514",
      "security_rejected"=>result.fetch("security_rejected") == true,
      "marker_exact"=>result.fetch("oracle_marker") == marker,
      "literal_tenant_policy_exact"=>result.fetch("policy_tenant") == "atlas_typed_order_writer"
    }
  end

  def query_types_constraints_pass?(result, marker:)
    query_types_constraints_predicates(result, marker: marker).values.all?
  end

  def performance_execution_plan_nodes(plan_document)
    plan_document_nodes(plan_document)
  end

  def plan_document_nodes(plan_document)
    return [] unless plan_document.is_a?(Array) && !plan_document.empty?

    root = plan_document.first["Plan"]
    return [] unless root.is_a?(Hash)

    plan_nodes(root)
  end

  def plan_nodes(node)
    children = Array(node["Plans"]).select { |child| child.is_a?(Hash) }
    [node] + children.flat_map { |child| plan_nodes(child) }
  end

  def plan_has_actual_execution?(nodes)
    nodes.any? do |node|
      numeric?(node["Actual Rows"]) && node["Actual Rows"] >= 0 &&
        numeric?(node["Actual Loops"]) && node["Actual Loops"] >= 1
    end
  end

  def plan_has_buffers?(nodes)
    nodes.any? do |node|
      BUFFER_KEYS.any? { |key| numeric?(node[key]) }
    end
  end

  def plan_has_exact_actual_rows?(nodes:, expected:)
    nodes.any? do |node|
      numeric?(node["Actual Rows"]) && node["Actual Rows"].to_i == expected.to_i &&
        numeric?(node["Actual Loops"]) && node["Actual Loops"] >= 1
    end
  end

  def exact_index_path?(nodes:, relation:, index:)
    nodes.any? do |node|
      INDEX_SCAN_NODE_TYPES.include?(node["Node Type"]) &&
        node["Relation Name"] == relation &&
        node["Index Name"] == index &&
        numeric?(node["Actual Rows"]) &&
        numeric?(node["Actual Loops"]) && node["Actual Loops"] >= 1
    end || bitmap_heap_index_path?(nodes: nodes, relation: relation, index: index)
  end

  def bitmap_heap_index_path?(nodes:, relation:, index:)
    nodes.any? do |node|
      node["Node Type"] == "Bitmap Heap Scan" &&
        node["Relation Name"] == relation &&
        numeric?(node["Actual Rows"]) &&
        numeric?(node["Actual Loops"]) && node["Actual Loops"] >= 1 &&
        Array(node["Plans"]).any? do |child|
          child.is_a?(Hash) &&
            child["Node Type"] == "Bitmap Index Scan" &&
            child["Index Name"] == index &&
            numeric?(child["Actual Loops"]) && child["Actual Loops"] >= 1
        end
    end
  end

  def seq_scan_absent_on_relation?(nodes:, relation:)
    nodes.none? do |node|
      node["Node Type"] == "Seq Scan" &&
        node["Relation Name"] == relation
    end
  end

  def condition_includes?(nodes:, expected:)
    nodes.any? do |node|
      ["Index Cond", "Recheck Cond", "Filter"].any? do |key|
        node[key].is_a?(String) && node[key].include?(expected)
      end
    end
  end

  def numeric?(value)
    value.is_a?(Numeric)
  end
end
