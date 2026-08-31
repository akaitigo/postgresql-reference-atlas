#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_next_runtime_rows"

plan = SecurityScenarioTranche.load_plan
rows = SecurityNextRuntimeRows.next_runtime_rows(plan)
source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))

abort "security runner must bind next runtime row selection helper" unless source.include?('require_relative "lib/security_next_runtime_rows"') &&
  source.include?("runtime_rows = SecurityNextRuntimeRows.next_runtime_rows(plan)") &&
  source.include?("SecurityNextRuntimeRows.verify_security_command_supported!(runtime_rows)")

begin
  SecurityNextRuntimeRows.verify_security_command_supported!(rows)
  abort "security-only runner unexpectedly accepted refusal rows"
rescue RuntimeError => e
  raise unless e.message.include?("unsupported scenarios: refusal")
end

security_only = SecurityNextRuntimeRows.completed_rows(plan)
abort "completed runtime rows should remain security-only" unless SecurityNextRuntimeRows.unsupported_scenarios(security_only).empty?
SecurityNextRuntimeRows.verify_security_command_supported!(security_only)

puts "Security next runtime scenario guardを検証しました: the current security-only command fails closed on refusal rows and still accepts the completed security-only suite"
