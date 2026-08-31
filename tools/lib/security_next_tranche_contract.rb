# frozen_string_literal: true

require "json"
require_relative "security_scenario_tranche"

module SecurityNextTrancheContract
  COMMAND = "ruby tools/run-scenario-security-001.rb"
  ATTEMPT_POLICY = {
    "workers"=>1,
    "retries"=>0,
    "first_attempt_only"=>true
  }.freeze
  PUBLICATION_POLICY = {
    "publish_on"=>"full-run-passed",
    "failed_run"=>"retain-prior-success",
    "swap"=>"staged-directory-rename-with-rollback"
  }.freeze
  DIAGNOSTIC_POLICY = {
    "output_root"=>"artifacts/pattern-scenario-failures",
    "append_only"=>true,
    "preserve_original_error"=>true,
    "canonical_pre_post_unchanged_required"=>true
  }.freeze

  module_function

  def contract
    {
      "tranche_id"=>"security-001",
      "scenario"=>"security",
      "command"=>COMMAND,
      "attempt_policy"=>ATTEMPT_POLICY,
      "publication_policy"=>PUBLICATION_POLICY,
      "diagnostic_policy"=>DIAGNOSTIC_POLICY,
      "row_ids"=>SecurityScenarioTranche.expected_row_ids,
      "pattern_rows"=>SecurityScenarioTranche::NEXT_TRANCHE_PATTERN_IDS.length,
      "variant_runs"=>SecurityScenarioTranche::NEXT_TRANCHE_PATTERN_IDS.length
    }
  end

  def verify!(plan: SecurityScenarioTranche.load_plan, candidate: contract)
    raise "next tranche contract tranche drifted" unless candidate.fetch("tranche_id") == "security-001"
    raise "next tranche contract scenario drifted" unless candidate.fetch("scenario") == "security"
    raise "next tranche contract command drifted" unless candidate.fetch("command") == COMMAND
    raise "next tranche contract attempt policy drifted" unless candidate.fetch("attempt_policy") == ATTEMPT_POLICY
    raise "next tranche contract publication policy drifted" unless candidate.fetch("publication_policy") == PUBLICATION_POLICY
    raise "next tranche contract diagnostic policy drifted" unless candidate.fetch("diagnostic_policy") == DIAGNOSTIC_POLICY
    raise "next tranche contract row_ids drifted" unless candidate.fetch("row_ids") == SecurityScenarioTranche.expected_row_ids
    raise "next tranche contract pattern_rows drifted" unless candidate.fetch("pattern_rows") == SecurityScenarioTranche::NEXT_TRANCHE_PATTERN_IDS.length
    raise "next tranche contract variant_runs drifted" unless candidate.fetch("variant_runs") == SecurityScenarioTranche::NEXT_TRANCHE_PATTERN_IDS.length

    tranche = SecurityScenarioTranche.verify_next_tranche!(plan)
    raise "next tranche contract is not bound to closure plan order" unless tranche.fetch("row_ids") == candidate.fetch("row_ids")
    raise "next tranche contract pattern_rows do not match closure plan" unless tranche.fetch("pattern_rows") == candidate.fetch("pattern_rows")
    raise "next tranche contract variant_runs do not match closure plan" unless tranche.fetch("variant_runs") == candidate.fetch("variant_runs")
    true
  end
end
