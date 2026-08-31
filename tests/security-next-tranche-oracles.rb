#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_scenario_oracles"

partitioning_marker = "ATLAS_SECURITY_PASS:query.partitioning"
partitioning_pass = {
  "server_version"=>"18.6",
  "observation_rows"=>1,
  "q1_rows"=>1,
  "q2_rows"=>1,
  "default_rows"=>1,
  "partition_pruning"=>true,
  "security_rejected"=>true,
  "oracle_marker"=>partitioning_marker,
  "verdict"=>"pass",
  "plan"=>[{"Plan"=>{
    "Node Type"=>"Append",
    "Actual Rows"=>1.0,
    "Actual Loops"=>1,
    "Shared Hit Blocks"=>2,
    "Plans"=>[
      {"Node Type"=>"Seq Scan", "Relation Name"=>"atlas_partition_secure_2026q1", "Actual Rows"=>1.0, "Actual Loops"=>1, "Shared Hit Blocks"=>2}
    ]
  }}]
}
abort "query.partitioning pass shape rejected" unless SecurityScenarioOracles.query_partitioning_pass?(partitioning_pass, marker: partitioning_marker)
abort "query.partitioning observation-row drift accepted" if SecurityScenarioOracles.query_partitioning_pass?(partitioning_pass.merge("observation_rows"=>2), marker: partitioning_marker)
abort "query.partitioning q2 leak accepted" if SecurityScenarioOracles.query_partitioning_pass?(partitioning_pass.merge("plan"=>[{"Plan"=>{"Node Type"=>"Append","Actual Rows"=>1.0,"Actual Loops"=>1,"Shared Hit Blocks"=>2,"Plans"=>[{"Node Type"=>"Seq Scan","Relation Name"=>"atlas_partition_secure_2026q1","Actual Rows"=>1.0,"Actual Loops"=>1,"Shared Hit Blocks"=>2},{"Node Type"=>"Seq Scan","Relation Name"=>"atlas_partition_secure_2026q2","Actual Rows"=>1.0,"Actual Loops"=>1,"Shared Hit Blocks"=>1}]}}]), marker: partitioning_marker)
abort "query.partitioning default partition leak accepted" if SecurityScenarioOracles.query_partitioning_pass?(partitioning_pass.merge("plan"=>[{"Plan"=>{"Node Type"=>"Append","Actual Rows"=>1.0,"Actual Loops"=>1,"Shared Hit Blocks"=>2,"Plans"=>[{"Node Type"=>"Seq Scan","Relation Name"=>"atlas_partition_secure_2026q1","Actual Rows"=>1.0,"Actual Loops"=>1,"Shared Hit Blocks"=>2},{"Node Type"=>"Seq Scan","Relation Name"=>"atlas_partition_secure_default","Actual Rows"=>1.0,"Actual Loops"=>1,"Shared Hit Blocks"=>1}]}}]), marker: partitioning_marker)
abort "query.partitioning detach failure missing accepted" if SecurityScenarioOracles.query_partitioning_pass?(partitioning_pass.merge("security_rejected"=>false), marker: partitioning_marker)
abort "query.partitioning pruning false accepted" if SecurityScenarioOracles.query_partitioning_pass?(partitioning_pass.merge("partition_pruning"=>false), marker: partitioning_marker)

security_marker = "ATLAS_SECURITY_PASS:query.security"
security_pass = {
  "server_version"=>"18.6",
  "observation_rows"=>1,
  "visible_rows"=>1,
  "tenant_escape_denied"=>true,
  "sqlstate"=>"42501",
  "password_encryption"=>"scram-sha-256",
  "scram_verifier"=>true,
  "host_rule_rows"=>[
    {"line_number"=>90, "type"=>"host", "database"=>["all"], "user_name"=>["all"], "address"=>"127.0.0.1/32", "auth_method"=>"scram-sha-256", "error"=>nil}
  ],
  "effective_host_rule"=>{"line_number"=>90, "type"=>"host", "database"=>["all"], "user_name"=>["all"], "address"=>"127.0.0.1/32", "auth_method"=>"scram-sha-256", "error"=>nil},
  "host_scram_rule"=>true,
  "fixed_search_path"=>true,
  "oracle_marker"=>security_marker,
  "verdict"=>"pass"
}
abort "query.security pass shape rejected" unless SecurityScenarioOracles.query_security_pass?(security_pass, marker: security_marker)
abort "query.security observation-row drift accepted" if SecurityScenarioOracles.query_security_pass?(security_pass.merge("observation_rows"=>0), marker: security_marker)
abort "query.security wrong sqlstate accepted" if SecurityScenarioOracles.query_security_pass?(security_pass.merge("sqlstate"=>"00000"), marker: security_marker)
abort "query.security visible-row drift accepted" if SecurityScenarioOracles.query_security_pass?(security_pass.merge("visible_rows"=>2), marker: security_marker)
abort "query.security scram verifier drift accepted" if SecurityScenarioOracles.query_security_pass?(security_pass.merge("scram_verifier"=>false), marker: security_marker)
abort "query.security missing host-rule rows accepted" if SecurityScenarioOracles.query_security_pass?(security_pass.merge("host_rule_rows"=>[]), marker: security_marker)
abort "query.security effective host-rule auth drift accepted" if SecurityScenarioOracles.query_security_pass?(security_pass.merge("effective_host_rule"=>security_pass.fetch("effective_host_rule").merge("auth_method"=>"md5")), marker: security_marker)
abort "query.security effective host-rule error drift accepted" if SecurityScenarioOracles.query_security_pass?(security_pass.merge("effective_host_rule"=>security_pass.fetch("effective_host_rule").merge("error"=>"parse error")), marker: security_marker)
abort "query.security search_path drift accepted" if SecurityScenarioOracles.query_security_pass?(security_pass.merge("fixed_search_path"=>false), marker: security_marker)

sql_surface_marker = "ATLAS_SECURITY_PASS:query.sql-surface"
sql_surface_pass = {
  "server_version"=>"18.6",
  "observation_rows"=>1,
  "returned_id"=>1,
  "returned_note"=>"created",
  "visible_rows"=>1,
  "duplicate_key_sqlstate"=>"23505",
  "check_violation_sqlstate"=>"23514",
  "policy_tenant"=>"atlas_sql_surface_writer",
  "security_rejected"=>true,
  "oracle_marker"=>sql_surface_marker,
  "verdict"=>"pass"
}
abort "query.sql-surface pass shape rejected" unless SecurityScenarioOracles.query_sql_surface_pass?(sql_surface_pass, marker: sql_surface_marker)
abort "query.sql-surface observation-row drift accepted" if SecurityScenarioOracles.query_sql_surface_pass?(sql_surface_pass.merge("observation_rows"=>0), marker: sql_surface_marker)
abort "query.sql-surface literal tenant drift accepted" if SecurityScenarioOracles.query_sql_surface_pass?(sql_surface_pass.merge("policy_tenant"=>"current_user"), marker: sql_surface_marker)
abort "query.sql-surface duplicate-key drift accepted" if SecurityScenarioOracles.query_sql_surface_pass?(sql_surface_pass.merge("duplicate_key_sqlstate"=>"00000"), marker: sql_surface_marker)
abort "query.sql-surface check-violation drift accepted" if SecurityScenarioOracles.query_sql_surface_pass?(sql_surface_pass.merge("check_violation_sqlstate"=>"00000"), marker: sql_surface_marker)
abort "query.sql-surface cross-tenant refusal drift accepted" if SecurityScenarioOracles.query_sql_surface_pass?(sql_surface_pass.merge("security_rejected"=>false), marker: sql_surface_marker)

types_marker = "ATLAS_SECURITY_PASS:query.types-constraints"
types_pass = {
  "server_version"=>"18.6",
  "observation_rows"=>1,
  "row_count"=>1,
  "uuid_version"=>7,
  "array_contains"=>true,
  "json_path"=>true,
  "range_contains"=>true,
  "generated_value"=>"atlas-order",
  "invalid_domain_sqlstate"=>"23514",
  "policy_tenant"=>"atlas_typed_order_writer",
  "security_rejected"=>true,
  "oracle_marker"=>types_marker,
  "verdict"=>"pass"
}
abort "query.types-constraints pass shape rejected" unless SecurityScenarioOracles.query_types_constraints_pass?(types_pass, marker: types_marker)
abort "query.types-constraints observation-row drift accepted" if SecurityScenarioOracles.query_types_constraints_pass?(types_pass.merge("observation_rows"=>2), marker: types_marker)
abort "query.types-constraints invalid-domain drift accepted" if SecurityScenarioOracles.query_types_constraints_pass?(types_pass.merge("invalid_domain_sqlstate"=>"00000"), marker: types_marker)
abort "query.types-constraints uuid version drift accepted" if SecurityScenarioOracles.query_types_constraints_pass?(types_pass.merge("uuid_version"=>4), marker: types_marker)
abort "query.types-constraints generated-value drift accepted" if SecurityScenarioOracles.query_types_constraints_pass?(types_pass.merge("generated_value"=>"other"), marker: types_marker)
abort "query.types-constraints cross-tenant refusal drift accepted" if SecurityScenarioOracles.query_types_constraints_pass?(types_pass.merge("security_rejected"=>false), marker: types_marker)

puts "Next security tranche oracle contractを検証しました: partitioning/security/sql-surface/types-constraints pass shapes accepted and representative pruning/sqlstate/scram/search_path/uuid/generated-value/cross-tenant regressions rejected"
