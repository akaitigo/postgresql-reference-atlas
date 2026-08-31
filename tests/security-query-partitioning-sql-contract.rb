#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_next_tranche_row_contracts"

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
section = source[/def query_partitioning_security_execution\(container\)(.*?)^end$/m, 1]
contract = SecurityNextTrancheRowContracts.contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.partitioning" } or abort("partitioning row contract missing")

abort "query.partitioning section is missing" unless section

errors = []
contract.fetch("sql_fragments").each do |fragment|
  errors << "missing SQL fragment: #{fragment}" unless section.include?(fragment)
end
contract.fetch("forbidden_sql_fragments").each do |fragment|
  errors << "forbidden SQL fragment present: #{fragment}" if section.include?(fragment)
end
errors << "structured failure binding drifted" unless section.include?('failed_row: "closure.definitive-domain.query.partitioning.security"') &&
  section.include?('target: "query.partitioning"') &&
  section.include?('oracle_error: "query.partitioning security Oracle failed"')
abort errors.join("\n") unless errors.empty?

current_user_regression = section.sub("USING (tenant = 'atlas_partition_reader')", "USING (tenant = current_user)")
abort "current_user partition policy regression was accepted" unless current_user_regression.include?("USING (tenant = current_user)")
abort "partitioning contract no longer forbids current_user regression" unless contract.fetch("forbidden_sql_fragments").include?("current_user")

public_policy_regression = section.sub("TO atlas_partition_reader", "TO PUBLIC")
abort "PUBLIC partition policy regression was accepted" unless public_policy_regression.include?("TO PUBLIC")
abort "partitioning contract no longer forbids PUBLIC policy regression" unless contract.fetch("forbidden_sql_fragments").include?("TO PUBLIC")

puts "query.partitioning SQL contractを検証しました: exact SQL fragments, forbidden current_user/PUBLIC regressions, and structured failure binding are fixed"
