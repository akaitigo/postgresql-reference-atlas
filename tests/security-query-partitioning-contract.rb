#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_next_tranche_row_contracts"

contract = SecurityNextTrancheRowContracts.contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.partitioning" } or abort("partitioning row contract missing")
abort "partitioning row contract target drifted" unless contract.fetch("target_id") == "query.partitioning"
abort "partitioning row contract proof obligation drifted" unless contract.fetch("proof_obligation_id") == "query.partition-routing-pruning"
abort "partitioning row contract must require exact partition routing SQL" unless contract.fetch("sql_fragments").include?("PARTITION BY RANGE (occurred_on)") && contract.fetch("sql_fragments").include?("ALTER TABLE atlas_partition_secure DETACH PARTITION atlas_partition_secure_2026q1")
abort "partitioning row contract must reject planner forcing and PUBLIC policy regressions" unless contract.fetch("forbidden_sql_fragments").include?("enable_partition_pruning = off") && contract.fetch("forbidden_sql_fragments").include?("TO PUBLIC")
abort "partitioning row contract must require exact pruning oracle predicates" unless contract.fetch("required_oracle_predicates").include?("plan_q1_partition_present") && contract.fetch("required_oracle_predicates").include?("plan_default_partition_absent")
abort "partitioning row contract must reject detach/pruning drift" unless contract.fetch("negative_cases").include?("detach_partition_allowed") && contract.fetch("negative_cases").include?("partition_pruning_missing")

weakened_sql = JSON.parse(JSON.generate(contract))
weakened_sql.fetch("sql_fragments").delete("PARTITION BY RANGE (occurred_on)")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_sql, contract)
  abort "weakened partitioning SQL was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sql_fragments drifted")
end

weakened_oracle = JSON.parse(JSON.generate(contract))
weakened_oracle.fetch("required_oracle_predicates").delete("plan_q2_partition_absent")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_oracle, contract)
  abort "weakened partitioning oracle predicates were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("required_oracle_predicates drifted")
end

weakened_negative = JSON.parse(JSON.generate(contract))
weakened_negative.fetch("negative_cases").delete("forced_partition_guc_present")
begin
  SecurityNextTrancheRowContracts.verify_contract_row!(weakened_negative, contract)
  abort "weakened partitioning negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negative_cases drifted")
end

puts "query.partitioning next tranche contractを検証しました: routing/pruning SQL and owner-boundary negatives are fixed"
