#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_query_catalog_inventory_contract"

contract = SecurityQueryCatalogInventoryContract.contract
SecurityQueryCatalogInventoryContract.verify!(contract)

tranche_source = File.read(File.expand_path("../tools/lib/security_published_tranche_contract.rb", __dir__))
abort "published tranche contract must reference query.catalog-inventory executor" unless tranche_source.include?('"executor_id"=>"catalog-inventory-security"')
abort "published tranche contract must bind query.catalog-inventory contract support path" unless tranche_source.include?('"tools/lib/security_query_catalog_inventory_contract.rb"')

deleted_sql = SecurityQueryCatalogInventoryContract.contract
deleted_sql.fetch("sql_fragments").delete("FROM pg_available_extensions")
begin
  SecurityQueryCatalogInventoryContract.verify!(deleted_sql)
  abort "deleted catalog inventory SQL fragment was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sql fragments drifted")
end

weakened_predicates = SecurityQueryCatalogInventoryContract.contract
weakened_predicates.fetch("required_oracle_predicates").delete("plan_reads_pg_catalog_type_relation")
begin
  SecurityQueryCatalogInventoryContract.verify!(weakened_predicates)
  abort "weakened catalog inventory oracle predicates were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("oracle predicates drifted")
end

weakened_negative = SecurityQueryCatalogInventoryContract.contract
weakened_negative.fetch("negative_cases").delete("unauthorized_catalog_mutation_allowed")
begin
  SecurityQueryCatalogInventoryContract.verify!(weakened_negative)
  abort "weakened catalog inventory negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negatives drifted")
end

weakened_diagnostic = SecurityQueryCatalogInventoryContract.contract
weakened_diagnostic.fetch("diagnostic_fields").delete("plan_nodes")
begin
  SecurityQueryCatalogInventoryContract.verify!(weakened_diagnostic)
  abort "weakened catalog inventory diagnostic fields were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("diagnostic fields drifted")
end

forbidden_removed = SecurityQueryCatalogInventoryContract.contract
forbidden_removed.fetch("forbidden_sql_fragments").delete("ALTER SYSTEM")
begin
  SecurityQueryCatalogInventoryContract.verify!(forbidden_removed)
  abort "removed catalog inventory forbidden SQL guard was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("forbidden sql drifted")
end

puts "query.catalog-inventory security contractを検証しました: SQL/oracle/negative/diagnostic guards are fixed"
