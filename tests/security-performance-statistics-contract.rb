#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_performance_statistics_contract"

contract = SecurityPerformanceStatisticsContract.contract
SecurityPerformanceStatisticsContract.verify!(contract)

source = File.read(File.expand_path("../tools/lib/security_published_tranche_contract.rb", __dir__))
abort "published tranche contract must reference performance.statistics executor" unless source.include?('"executor_id"=>"performance-statistics-security"')
runner = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
abort "performance.statistics must map PostgreSQL stxkind f to dependencies" unless runner.include?("WHEN 'f' THEN 'dependencies'")
abort "performance.statistics must not map ndistinct stxkind d to dependencies" if runner.include?("WHEN 'd' THEN 'dependencies'")

deleted_sql = SecurityPerformanceStatisticsContract.contract
deleted_sql.fetch("sql_fragments").delete("ANALYZE correlated_fact;")
begin
  SecurityPerformanceStatisticsContract.verify!(deleted_sql)
  abort "deleted statistics SQL fragment was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sql fragments drifted")
end

weakened_predicates = SecurityPerformanceStatisticsContract.contract
weakened_predicates.fetch("required_oracle_predicates").delete("plan_rows_match_estimate")
begin
  SecurityPerformanceStatisticsContract.verify!(weakened_predicates)
  abort "weakened statistics oracle predicates were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("oracle predicates drifted")
end

weakened_negative = SecurityPerformanceStatisticsContract.contract
weakened_negative.fetch("negative_cases").delete("unauthorized_analyze_allowed")
begin
  SecurityPerformanceStatisticsContract.verify!(weakened_negative)
  abort "weakened statistics negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negatives drifted")
end

weakened_diagnostic = SecurityPerformanceStatisticsContract.contract
weakened_diagnostic.fetch("diagnostic_fields").delete("plan_nodes")
begin
  SecurityPerformanceStatisticsContract.verify!(weakened_diagnostic)
  abort "weakened statistics diagnostic fields were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("diagnostic fields drifted")
end

forbidden_removed = SecurityPerformanceStatisticsContract.contract
forbidden_removed.fetch("forbidden_sql_fragments").delete("enable_seqscan")
begin
  SecurityPerformanceStatisticsContract.verify!(forbidden_removed)
  abort "removed forbidden SQL guard was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("forbidden sql drifted")
end

puts "performance.statistics security contractを検証しました: SQL/oracle/negative/diagnostic guards are fixed"
