# frozen_string_literal: true

require "json"
require_relative "security_next_tranche_contract"
require_relative "security_scenario_tranche"

module SecurityRuntimeReadinessContract
  COMMAND = "ruby tools/run-scenario-security-001.rb"
  TRANCHE_ID = "security-001"
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
  SUMMARY = {
    "completed_dedicated_rows"=>24,
    "remaining_rows"=>266,
    "planned_tranches"=>74
  }.freeze
  CONTRACT = {
    "tranche_id"=>TRANCHE_ID,
    "scenario"=>"security",
    "status"=>"not-ready",
    "command"=>COMMAND,
    "attempt_policy"=>ATTEMPT_POLICY,
    "publication_policy"=>PUBLICATION_POLICY,
    "row_ids"=>SecurityScenarioTranche.expected_row_ids,
    "blocked_by"=>[
      "next-security-row-contracts-not-authored",
      "next-security-runtime-oracles-not-authored",
      "next-security-runtime-support-paths-not-bound"
    ]
  }.freeze

  module_function

  def contract
    JSON.parse(JSON.generate(CONTRACT.merge("summary"=>SUMMARY)))
  end

  def verify_contract!(candidate = contract, plan: SecurityScenarioTranche.load_plan)
    SecurityNextTrancheContract.verify!(plan: plan)
    raise "security runtime readiness tranche drifted" unless candidate.fetch("tranche_id") == TRANCHE_ID
    raise "security runtime readiness scenario drifted" unless candidate.fetch("scenario") == "security"
    raise "security runtime readiness status drifted" unless candidate.fetch("status") == "not-ready"
    raise "security runtime readiness command drifted" unless candidate.fetch("command") == COMMAND
    raise "security runtime readiness attempt policy drifted" unless candidate.fetch("attempt_policy") == ATTEMPT_POLICY
    raise "security runtime readiness publication policy drifted" unless candidate.fetch("publication_policy") == PUBLICATION_POLICY
    raise "security runtime readiness row_ids drifted" unless candidate.fetch("row_ids") == SecurityScenarioTranche.expected_row_ids
    raise "security runtime readiness blocked_by drifted" unless candidate.fetch("blocked_by") == CONTRACT.fetch("blocked_by")
    raise "security runtime readiness summary drifted" unless candidate.fetch("summary") == SUMMARY
    raise "security runtime readiness completed/remaining summary drifted" unless plan.fetch("summary").slice(*SUMMARY.keys) == SUMMARY
    true
  end

  def verify_runnable!(plan: SecurityScenarioTranche.load_plan)
    verify_contract!(plan: plan)
    raise "security runtime readiness is not complete for #{TRANCHE_ID}" unless contract.fetch("status") == "ready"
    true
  end
end
