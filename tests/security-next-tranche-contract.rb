#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_next_tranche_contract"
require_relative "../tools/lib/security_next_tranche_row_contracts"

plan = SecurityScenarioTranche.load_plan
SecurityNextTrancheContract.verify!(plan: plan)
source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
abort "security runner must bind next tranche contract preflight" unless source.include?('require_relative "lib/security_next_tranche_contract"') && source.include?("SecurityNextTrancheContract.verify!(plan: plan)")
abort "security runner must bind next tranche row contracts preflight" unless source.include?('require_relative "lib/security_next_tranche_row_contracts"') && source.include?("SecurityNextTrancheRowContracts.verify!")
abort "security runner must fail closed on missing next tranche definitions" unless source.include?('raise "security runtime definitions missing:')

contract = SecurityNextTrancheContract.contract
row_contracts = SecurityNextTrancheRowContracts.contracts
completed_ids = plan.fetch("completed_rows").map { |row| SecurityScenarioTranche.row_id_for(row.fetch("pattern_id")) }
abort "next tranche contract row_ids drifted" unless contract.fetch("row_ids") == SecurityScenarioTranche.expected_latest_runtime_row_ids
abort "next tranche contract must stay bound to the completed suite" unless (contract.fetch("row_ids") - completed_ids).empty?
abort "next tranche contract must stay exact 4 rows" unless contract.fetch("pattern_rows") == 4 && contract.fetch("variant_runs") == 4
abort "next tranche row contracts must stay exact 4 rows" unless row_contracts.length == 4
abort "next tranche command drifted" unless contract.fetch("command") == SecurityNextTrancheContract::COMMAND
abort "next tranche attempt policy drifted" unless SecurityNextTrancheContract::ATTEMPT_POLICY == {"workers"=>1, "retries"=>0, "first_attempt_only"=>true}
abort "next tranche publication policy drifted" unless SecurityNextTrancheContract::PUBLICATION_POLICY == {
  "publish_on"=>"full-run-passed",
  "failed_run"=>"retain-prior-success",
  "swap"=>"staged-directory-rename-with-rollback"
}
abort "next tranche diagnostic policy drifted" unless SecurityNextTrancheContract::DIAGNOSTIC_POLICY == {
  "output_root"=>"artifacts/pattern-scenario-failures",
  "append_only"=>true,
  "preserve_original_error"=>true,
  "canonical_pre_post_unchanged_required"=>true
}

deleted = JSON.parse(JSON.generate(contract))
deleted["row_ids"] = deleted.fetch("row_ids").first(3)
deleted["pattern_rows"] = 3
deleted["variant_runs"] = 3
begin
  SecurityNextTrancheContract.verify!(plan: plan, candidate: deleted)
  abort "deleted next tranche contract row was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("row_ids drifted")
end

reordered = JSON.parse(JSON.generate(contract))
reordered["row_ids"] = reordered.fetch("row_ids").reverse
begin
  SecurityNextTrancheContract.verify!(plan: plan, candidate: reordered)
  abort "reordered next tranche contract rows were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("row_ids drifted")
end

command_weakened = JSON.parse(JSON.generate(contract))
command_weakened["command"] = "ruby tools/run-scenario-security-002.rb"
begin
  SecurityNextTrancheContract.verify!(plan: plan, candidate: command_weakened)
  abort "weakened next tranche command was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("command drifted")
end

retry_weakened = JSON.parse(JSON.generate(contract))
retry_weakened.fetch("attempt_policy")["retries"] = 1
begin
  SecurityNextTrancheContract.verify!(plan: plan, candidate: retry_weakened)
  abort "weakened next tranche retries were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("attempt policy drifted")
end

diagnostic_weakened = JSON.parse(JSON.generate(contract))
diagnostic_weakened.fetch("diagnostic_policy")["append_only"] = false
begin
  SecurityNextTrancheContract.verify!(plan: plan, candidate: diagnostic_weakened)
  abort "weakened next tranche diagnostic policy was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("diagnostic policy drifted")
end

puts "Security runtime tranche contractを検証しました: completed query 4-row contract remains fixed, bound to the completed suite, and command/publication/diagnostic weakening is rejected"
