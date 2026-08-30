#!/usr/bin/env ruby
# frozen_string_literal: true

SOURCE_PATH = File.expand_path("../tools/run-scenario-security-001.rb", __dir__)
source = File.read(SOURCE_PATH)
section = source[/def performance_execution_security_execution\(container\)(.*?)^end$/m, 1]
literal_tenant = "atlas_perf_execution_reader"

abort "performance.execution section is missing" unless section

def contract_errors(source:, section:, literal_tenant:)
  errors = []
  policy_block = /CREATE POLICY atlas_perf_execution_policy ON atlas_perf_execution_secure\s+TO atlas_perf_execution_reader\s+USING \(tenant = '#\{PERFORMANCE_EXECUTION_LITERAL_TENANT\}'\)\s+WITH CHECK \(tenant = '#\{PERFORMANCE_EXECUTION_LITERAL_TENANT\}'\);/m
  errors << "fixture row count drifted" unless section.include?("FROM generate_series(1, 200000) AS g;")
  errors << "visible row contract drifted" unless section.include?("'visible_rows', visible_rows")
  errors << "literal tenant constant drifted" unless source.include?("PERFORMANCE_EXECUTION_LITERAL_TENANT = \"#{literal_tenant}\"")
  errors << "policy role scope drifted" unless section.match?(policy_block)
  errors << "policy USING predicate must use literal tenant constant" unless section.include?(%q{USING (tenant = '#{PERFORMANCE_EXECUTION_LITERAL_TENANT}')})
  errors << "policy WITH CHECK predicate must use literal tenant constant" unless section.include?(%q{WITH CHECK (tenant = '#{PERFORMANCE_EXECUTION_LITERAL_TENANT}')})
  errors << "explain query must use literal tenant predicate constant" unless section.include?(%q{WHERE tenant = ''#{PERFORMANCE_EXECUTION_LITERAL_TENANT}'' ORDER BY id})
  errors << "visible row query must use literal tenant predicate constant" unless section.include?(%q{WHERE tenant = '#{PERFORMANCE_EXECUTION_LITERAL_TENANT}'})
  errors << "cross-tenant insert refusal drifted" unless section.include?("VALUES (300001, 'postgres', 'forged')") && section.include?("RLS unexpectedly allowed cross-tenant insert")
  errors << "policy regressed to CURRENT_USER predicate" if section.include?("USING (tenant = current_user)") || section.include?("WITH CHECK (tenant = current_user)")
  errors << "explain query regressed to CURRENT_USER predicate" if section.include?("EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) SELECT id FROM atlas_perf_execution_secure WHERE tenant = current_user ORDER BY id")
  errors << "visible row query regressed to CURRENT_USER predicate" if section.include?("SELECT count(*) FROM atlas_perf_execution_secure WHERE tenant = current_user")
  errors << "PUBLIC RLS policy is forbidden" if section.include?("TO PUBLIC")
  errors << "planner forcing GUC is forbidden" if section.match?(/\benable_(seqscan|indexscan|bitmapscan)\b/)
  errors
end

errors = contract_errors(source: source, section: section, literal_tenant: literal_tenant)
abort errors.join("\n") unless errors.empty?

literal_missing = source.sub('PERFORMANCE_EXECUTION_LITERAL_TENANT = "atlas_perf_execution_reader"', 'PERFORMANCE_EXECUTION_LITERAL_TENANT = "missing_literal"')
errors = contract_errors(source: literal_missing, section: literal_missing[/def performance_execution_security_execution\(container\)(.*?)^end$/m, 1], literal_tenant: literal_tenant)
abort "literal tenant value drift was accepted" unless errors.include?("literal tenant constant drifted")

current_user_regression = source.sub("WHERE tenant = ''\#{PERFORMANCE_EXECUTION_LITERAL_TENANT}'' ORDER BY id", "WHERE tenant = current_user ORDER BY id")
errors = contract_errors(source: current_user_regression, section: current_user_regression[/def performance_execution_security_execution\(container\)(.*?)^end$/m, 1], literal_tenant: literal_tenant)
abort "current_user explain regression was accepted" unless errors.include?("explain query must use literal tenant predicate constant") && errors.include?("explain query regressed to CURRENT_USER predicate")

policy_current_user_regression = source.sub("USING (tenant = '\#{PERFORMANCE_EXECUTION_LITERAL_TENANT}')", "USING (tenant = current_user)")
errors = contract_errors(source: policy_current_user_regression, section: policy_current_user_regression[/def performance_execution_security_execution\(container\)(.*?)^end$/m, 1], literal_tenant: literal_tenant)
abort "current_user policy regression was accepted" unless errors.include?("policy USING predicate must use literal tenant constant") && errors.include?("policy regressed to CURRENT_USER predicate")

missing_role_scope_section = section.sub(/^\s+TO atlas_perf_execution_reader\n/, "")
errors = contract_errors(source: source, section: missing_role_scope_section, literal_tenant: literal_tenant)
abort "missing TO role scope was accepted" unless errors.include?("policy role scope drifted")

public_policy_section = section.sub("TO atlas_perf_execution_reader", "TO PUBLIC")
errors = contract_errors(source: source, section: public_policy_section, literal_tenant: literal_tenant)
abort "PUBLIC RLS policy was accepted" unless errors.include?("policy role scope drifted") && errors.include?("PUBLIC RLS policy is forbidden")

policy_literal_mismatch = source.sub("USING (tenant = '\#{PERFORMANCE_EXECUTION_LITERAL_TENANT}')", "USING (tenant = 'atlas_other_reader')")
errors = contract_errors(source: policy_literal_mismatch, section: policy_literal_mismatch[/def performance_execution_security_execution\(container\)(.*?)^end$/m, 1], literal_tenant: literal_tenant)
abort "policy literal mismatch was accepted" unless errors.include?("policy USING predicate must use literal tenant constant")

other_tenant = source.sub("WHERE tenant = '\#{PERFORMANCE_EXECUTION_LITERAL_TENANT}'", "WHERE tenant = 'atlas_other_reader'")
errors = contract_errors(source: other_tenant, section: other_tenant[/def performance_execution_security_execution\(container\)(.*?)^end$/m, 1], literal_tenant: literal_tenant)
abort "other-tenant visible count predicate was accepted" unless errors.include?("visible row query must use literal tenant predicate constant")

cross_tenant_write_allowed = source.sub("VALUES (300001, 'postgres', 'forged')", "VALUES (300001, 'atlas_perf_execution_reader', 'forged')")
errors = contract_errors(source: cross_tenant_write_allowed, section: cross_tenant_write_allowed[/def performance_execution_security_execution\(container\)(.*?)^end$/m, 1], literal_tenant: literal_tenant)
abort "cross-tenant write regression was accepted" unless errors.include?("cross-tenant insert refusal drifted")

forced_guc = source.sub("    BEGIN\n      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON)", "    BEGIN\n      SET LOCAL enable_seqscan = off;\n      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON)")
errors = contract_errors(source: forced_guc, section: forced_guc[/def performance_execution_security_execution\(container\)(.*?)^end$/m, 1], literal_tenant: literal_tenant)
abort "planner forcing GUC was accepted" unless errors.include?("planner forcing GUC is forbidden")

puts "performance.execution SQL contractを検証しました: role-scoped literal policy/query, cross-tenant refusal, and missing-TO/PUBLIC/current_user/literal-mismatch/other-tenant/GUC negatives rejected"
