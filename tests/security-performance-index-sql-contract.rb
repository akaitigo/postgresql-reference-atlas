#!/usr/bin/env ruby
# frozen_string_literal: true

SOURCE_PATH = File.expand_path("../tools/run-scenario-security-001.rb", __dir__)
source = File.read(SOURCE_PATH)
section = source[/def performance_index_security_execution\(container\)(.*?)^end$/m, 1]
literal_tenant = "atlas_perf_index_reader"

abort "performance.index section is missing" unless section

def contract_errors(source:, section:, literal_tenant:)
  errors = []
  policy_block = /CREATE POLICY atlas_perf_index_policy ON atlas_perf_index_secure\s+TO atlas_perf_index_reader\s+USING \(tenant = '#\{PERFORMANCE_INDEX_LITERAL_TENANT\}'\)\s+WITH CHECK \(tenant = '#\{PERFORMANCE_INDEX_LITERAL_TENANT\}'\);/m
  errors << "fixture row count drifted" unless section.include?("FROM generate_series(1, 200000) AS g;")
  errors << "literal tenant constant drifted" unless source.include?("PERFORMANCE_INDEX_LITERAL_TENANT = \"#{literal_tenant}\"")
  errors << "policy role scope drifted" unless section.match?(policy_block)
  errors << "policy USING predicate must use literal tenant constant" unless section.include?(%q{USING (tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}')})
  errors << "policy WITH CHECK predicate must use literal tenant constant" unless section.include?(%q{WITH CHECK (tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}')})
  errors << "independent billed distribution drifted" unless section.include?("((g / 1000) % 2 = 0)")
  errors << "explain query must use literal tenant billed predicate constant" unless section.include?(%q{WHERE tenant = ''#{PERFORMANCE_INDEX_LITERAL_TENANT}'' AND billed ORDER BY id})
  billed_predicate_count = section.scan(%q{WHERE tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}' AND billed}).length
  tenant_predicate_count = section.scan(%q{WHERE tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}'}).length
  errors << "before/after billed literal tenant predicate binding drifted" unless billed_predicate_count == 3
  errors << "tenant total literal predicate binding drifted" unless tenant_predicate_count >= 4
  errors << "partial index predicate capture drifted" unless section.include?("'index_predicate'") && section.include?("WHERE c.relname = 'atlas_perf_index_billed_idx'")
  errors << "tenant/billed result fields drifted" unless section.include?("'tenant_rows', tenant_rows") && section.include?("'billed_visible_rows', billed_visible_rows")
  errors << "cross-tenant insert refusal drifted" unless section.include?("VALUES (300001, 'postgres', true, 'forged')") && section.include?("RLS unexpectedly allowed cross-tenant insert")
  errors << "policy regressed to CURRENT_USER predicate" if section.include?("USING (tenant = current_user)") || section.include?("WITH CHECK (tenant = current_user)")
  errors << "query regressed to CURRENT_USER predicate" if section.include?("WHERE tenant = current_user AND billed")
  errors << "PUBLIC RLS policy is forbidden" if section.include?("TO PUBLIC")
  errors << "planner forcing GUC is forbidden" if section.match?(/\benable_(seqscan|indexscan|bitmapscan)\b/)
  errors
end

errors = contract_errors(source: source, section: section, literal_tenant: literal_tenant)
abort errors.join("\n") unless errors.empty?

literal_missing = source.sub('PERFORMANCE_INDEX_LITERAL_TENANT = "atlas_perf_index_reader"', 'PERFORMANCE_INDEX_LITERAL_TENANT = "missing_literal"')
errors = contract_errors(source: literal_missing, section: literal_missing[/def performance_index_security_execution\(container\)(.*?)^end$/m, 1], literal_tenant: literal_tenant)
abort "literal tenant value drift was accepted" unless errors.include?("literal tenant constant drifted")

missing_role_scope_section = section.sub(/^\s+TO atlas_perf_index_reader\n/, "")
errors = contract_errors(source: source, section: missing_role_scope_section, literal_tenant: literal_tenant)
abort "missing TO role scope was accepted" unless errors.include?("policy role scope drifted")

public_policy_section = section.sub("TO atlas_perf_index_reader", "TO PUBLIC")
errors = contract_errors(source: source, section: public_policy_section, literal_tenant: literal_tenant)
abort "PUBLIC RLS policy was accepted" unless errors.include?("policy role scope drifted") && errors.include?("PUBLIC RLS policy is forbidden")

policy_current_user_regression = section.sub("USING (tenant = '\#{PERFORMANCE_INDEX_LITERAL_TENANT}')", "USING (tenant = current_user)")
errors = contract_errors(source: source, section: policy_current_user_regression, literal_tenant: literal_tenant)
abort "current_user policy regression was accepted" unless errors.include?("policy USING predicate must use literal tenant constant") && errors.include?("policy regressed to CURRENT_USER predicate")

other_tenant = section.sub("WHERE tenant = '\#{PERFORMANCE_INDEX_LITERAL_TENANT}' AND billed", "WHERE tenant = 'atlas_other_reader' AND billed")
errors = contract_errors(source: source, section: other_tenant, literal_tenant: literal_tenant)
abort "other-tenant predicate regression was accepted" unless errors.include?("before/after billed literal tenant predicate binding drifted")

current_user_regression = section.sub("WHERE tenant = ''\#{PERFORMANCE_INDEX_LITERAL_TENANT}'' AND billed ORDER BY id", "WHERE tenant = current_user AND billed ORDER BY id")
errors = contract_errors(source: source, section: current_user_regression, literal_tenant: literal_tenant)
abort "current_user query regression was accepted" unless errors.include?("explain query must use literal tenant billed predicate constant") && errors.include?("query regressed to CURRENT_USER predicate")

all_even_tenant_fixture = section.sub("((g / 1000) % 2 = 0)", "(g % 2 = 0)")
errors = contract_errors(source: source, section: all_even_tenant_fixture, literal_tenant: literal_tenant)
abort "all-even tenant fixture regression was accepted" unless errors.include?("independent billed distribution drifted")

cross_tenant_write_allowed = section.sub("VALUES (300001, 'postgres', true, 'forged')", "VALUES (300001, 'atlas_perf_index_reader', true, 'forged')")
errors = contract_errors(source: source, section: cross_tenant_write_allowed, literal_tenant: literal_tenant)
abort "cross-tenant write regression was accepted" unless errors.include?("cross-tenant insert refusal drifted")

forced_guc = section.sub("    BEGIN\n      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON)", "    BEGIN\n      SET LOCAL enable_seqscan = off;\n      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON)")
errors = contract_errors(source: source, section: forced_guc, literal_tenant: literal_tenant)
abort "planner forcing GUC was accepted" unless errors.include?("planner forcing GUC is forbidden")

puts "performance.index SQL contractを検証しました: role-scoped literal policy/query, independent billed distribution, tenant total + billed result fields, partial-index predicate capture, and missing-TO/PUBLIC/current_user/literal-mismatch/other-tenant/all-even/GUC negatives rejected"
