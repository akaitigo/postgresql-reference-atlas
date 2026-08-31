#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_query_extension_contract"

contract = SecurityQueryExtensionContract.contract
SecurityQueryExtensionContract.verify!(contract)

tranche_source = File.read(File.expand_path("../tools/lib/security_published_tranche_contract.rb", __dir__))
abort "published tranche contract must reference query.extension executor" unless tranche_source.include?('"executor_id"=>"bundled-extension-security"')
abort "published tranche contract must bind query.extension contract support path" unless tranche_source.include?('"tools/lib/security_query_extension_contract.rb"')

deleted_sql = SecurityQueryExtensionContract.contract
deleted_sql.fetch("sql_fragments").delete("CREATE EXTENSION pg_trgm;")
begin
  SecurityQueryExtensionContract.verify!(deleted_sql)
  abort "deleted query.extension SQL fragment was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sql fragments drifted")
end

weakened_predicates = SecurityQueryExtensionContract.contract
weakened_predicates.fetch("required_oracle_predicates").delete("plan_exact_gin_index")
begin
  SecurityQueryExtensionContract.verify!(weakened_predicates)
  abort "weakened query.extension oracle predicates were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("oracle predicates drifted")
end

weakened_negative = SecurityQueryExtensionContract.contract
weakened_negative.fetch("negative_cases").delete("unauthorized_extension_install_allowed")
begin
  SecurityQueryExtensionContract.verify!(weakened_negative)
  abort "weakened query.extension negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negatives drifted")
end

weakened_diagnostic = SecurityQueryExtensionContract.contract
weakened_diagnostic.fetch("diagnostic_fields").delete("plan_nodes")
begin
  SecurityQueryExtensionContract.verify!(weakened_diagnostic)
  abort "weakened query.extension diagnostic fields were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("diagnostic fields drifted")
end

forbidden_removed = SecurityQueryExtensionContract.contract
forbidden_removed.fetch("forbidden_sql_fragments").delete("TO PUBLIC")
begin
  SecurityQueryExtensionContract.verify!(forbidden_removed)
  abort "removed query.extension forbidden SQL guard was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("forbidden sql drifted")
end

runner_source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
policy_fragment = "USING (tenant = 'atlas_extension_reader' AND body LIKE '%searchable phrase%')"
abort "query.extension runtime must bind the body predicate inside the role-scoped RLS policy" unless runner_source.include?(policy_fragment)
abort "query.extension runtime must bind the same body predicate in the policy and result query" unless runner_source.scan("body LIKE '%searchable phrase%'").length >= 2
abort "query.extension EXPLAIN must retain the same literal body predicate" unless runner_source.include?("body LIKE ''%searchable phrase%''")

weakened_policy = SecurityQueryExtensionContract.contract
weakened_policy.fetch("sql_fragments").map! do |fragment|
  fragment == policy_fragment ? "USING (tenant = 'atlas_extension_reader')" : fragment
end
begin
  SecurityQueryExtensionContract.verify!(weakened_policy)
  abort "query.extension policy without the body predicate was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sql fragments drifted")
end

puts "query.extension security contractを検証しました: SQL/oracle/negative/diagnostic guards are fixed"
