#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_published_tranche_contract"

plan = SecurityScenarioTranche.load_plan
contracts = SecurityPublishedTrancheContract.contracts
SecurityPublishedTrancheContract.verify!(plan: plan, contracts: contracts)

abort "published tranche contract row_ids drifted" unless SecurityPublishedTrancheContract.row_ids(contracts) == SecurityScenarioTranche.expected_published_row_ids
abort "published tranche contract must stay exact 4 rows" unless contracts.length == 4
abort "published tranche command drifted" unless contracts.all? { |row| row.fetch("command") == SecurityPublishedTrancheContract::COMMAND }
abort "published tranche attempt policy drifted" unless SecurityPublishedTrancheContract::ATTEMPT_POLICY == {"workers"=>1, "retries"=>0, "first_attempt_only"=>true}
abort "published tranche publication policy drifted" unless SecurityPublishedTrancheContract::PUBLICATION_POLICY == {
  "publish_on"=>"full-run-passed",
  "failed_run"=>"retain-prior-success",
  "swap"=>"staged-directory-rename-with-rollback"
}
abort "published tranche diagnostic policy drifted" unless SecurityPublishedTrancheContract::DIAGNOSTIC_POLICY == {
  "output_root"=>"artifacts/pattern-scenario-failures",
  "append_only"=>true,
  "preserve_original_error"=>true,
  "canonical_pre_post_unchanged_required"=>true
}

deleted = SecurityPublishedTrancheContract.contracts
deleted.pop
begin
  SecurityPublishedTrancheContract.verify!(plan: plan, contracts: deleted, verify_files: false)
  abort "deleted published tranche row was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("cardinality")
end

reordered = SecurityPublishedTrancheContract.contracts.reverse
begin
  SecurityPublishedTrancheContract.verify!(plan: plan, contracts: reordered, verify_files: false)
  abort "reordered published tranche rows were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("pattern order")
end

oracle_weakened = SecurityPublishedTrancheContract.contracts
oracle_weakened.first["oracle_id"] = "generic-security-oracle"
begin
  SecurityPublishedTrancheContract.verify!(plan: plan, contracts: oracle_weakened, verify_files: false)
  abort "weakened published tranche oracle contract was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("oracle_id drifted")
end

negative_removed = SecurityPublishedTrancheContract.contracts
negative_removed.first["negative_cases"] = negative_removed.first.fetch("negative_cases").first(3)
begin
  SecurityPublishedTrancheContract.verify!(plan: plan, contracts: negative_removed, verify_files: false)
  abort "weakened published tranche negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negatives weakened")
end

command_weakened = SecurityPublishedTrancheContract.contracts
command_weakened.first["command"] = "ruby tools/run-scenario-security-002.rb"
begin
  SecurityPublishedTrancheContract.verify!(plan: plan, contracts: command_weakened, verify_files: false)
  abort "weakened published tranche command was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("command drifted")
end

path_missing = SecurityPublishedTrancheContract.contracts
path_missing.last["support_paths"] = path_missing.last.fetch("support_paths") - ["labs/extension/verify.sql"]
begin
  SecurityPublishedTrancheContract.verify!(plan: plan, contracts: path_missing, verify_files: false)
  abort "missing published tranche support path was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("support_paths drifted")
end

puts "Published security tranche contractを検証しました: exact 4 published rows, command/publication/diagnostic policies, and deletion/reorder/weakening rejected"
