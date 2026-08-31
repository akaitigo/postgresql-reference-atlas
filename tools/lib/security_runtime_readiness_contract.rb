# frozen_string_literal: true

require "json"
require "open3"
require "time"
require_relative "security_next_tranche_contract"
require_relative "security_scenario_tranche"

module SecurityRuntimeReadinessContract
  ROOT = File.expand_path("../..", __dir__)
  COMMAND = "ruby tools/run-scenario-security-001.rb"
  TRANCHE_ID = "security-001"
  MINIMUM_FREE_GIB = 4
  PREFLIGHT_KIND = "postgresql-security-runtime-preflight-v1"
  SLOT_TOKEN_ENV = "PG_ATLAS_EXCLUSIVE_HEAVY_SLOT_TOKEN"
  MAX_PREFLIGHT_AGE_SECONDS = 60
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
    "completed_dedicated_rows"=>28,
    "remaining_rows"=>262,
    "planned_tranches"=>73
  }.freeze
  RUNTIME_PREREQUISITES = {
    "exclusive_heavy_slot_required"=>true,
    "minimum_free_gib"=>MINIMUM_FREE_GIB,
    "docker_active_containers"=>0
  }.freeze
  CONTRACT = {
    "tranche_id"=>TRANCHE_ID,
    "scenario"=>"security",
    "status"=>"not-ready",
    "command"=>COMMAND,
    "attempt_policy"=>ATTEMPT_POLICY,
    "publication_policy"=>PUBLICATION_POLICY,
    "row_ids"=>SecurityScenarioTranche.expected_latest_runtime_row_ids,
    "expected_outputs"=>[
      "artifacts/pattern-scenarios/results.json",
      "artifacts/pattern-scenarios/traces/definitive-domain_query_partitioning__security__postgresql-verification-matrix-v2.trace.json",
      "artifacts/pattern-scenarios/traces/definitive-domain_query_security__security__postgresql-verification-matrix-v2.trace.json",
      "artifacts/pattern-scenarios/traces/definitive-domain_query_sql-surface__security__postgresql-verification-matrix-v2.trace.json",
      "artifacts/pattern-scenarios/traces/definitive-domain_query_types-constraints__security__postgresql-verification-matrix-v2.trace.json",
      "artifacts/pattern-scenarios/observations/definitive-domain_query_partitioning__security__postgresql-verification-matrix-v2.observable.json",
      "artifacts/pattern-scenarios/observations/definitive-domain_query_security__security__postgresql-verification-matrix-v2.observable.json",
      "artifacts/pattern-scenarios/observations/definitive-domain_query_sql-surface__security__postgresql-verification-matrix-v2.observable.json",
      "artifacts/pattern-scenarios/observations/definitive-domain_query_types-constraints__security__postgresql-verification-matrix-v2.observable.json"
    ],
    "runtime_prerequisites"=>RUNTIME_PREREQUISITES,
    "blocked_by"=>[
      "live-slot-token-and-run-context-required"
    ]
  }.freeze

  module_function

  def contract
    JSON.parse(JSON.generate(CONTRACT.merge("summary"=>SUMMARY)))
  end

  def evaluate_live_preflight!(plan: SecurityScenarioTranche.load_plan, env: ENV.to_h, now: Time.now.utc,
                               pid: Process.pid, repo_root: ROOT, cwd: Dir.pwd, measurements: nil)
    verify_contract!(plan: plan)
    normalized_env = env.to_h
    measured = normalize_measurements(measurements || current_measurements(repo_root: repo_root))
    candidate = {
      "schema_version"=>1,
      "kind"=>PREFLIGHT_KIND,
      "tranche_id"=>TRANCHE_ID,
      "scenario"=>"security",
      "command"=>COMMAND,
      "attempt_policy"=>ATTEMPT_POLICY,
      "publication_policy"=>PUBLICATION_POLICY,
      "row_ids"=>SecurityScenarioTranche.expected_latest_runtime_row_ids,
      "expected_outputs"=>CONTRACT.fetch("expected_outputs"),
      "runtime_prerequisites"=>RUNTIME_PREREQUISITES,
      "repo_root"=>repo_root,
      "cwd"=>cwd,
      "pid"=>pid,
      "slot_token_env"=>SLOT_TOKEN_ENV,
      "slot_token"=>normalized_env[SLOT_TOKEN_ENV],
      "measured_at"=>now.utc.iso8601,
      "measurements"=>measured
    }
    failures = preflight_failures(candidate, env: normalized_env, now: now, pid: pid, repo_root: repo_root, cwd: cwd)
    candidate["status"] = failures.empty? ? "ready" : "blocked"
    candidate["failures"] = failures
    candidate
  end

  def verify_contract!(candidate = contract, plan: SecurityScenarioTranche.load_plan)
    SecurityNextTrancheContract.verify!(plan: plan)
    raise "security runtime readiness tranche drifted" unless candidate.fetch("tranche_id") == TRANCHE_ID
    raise "security runtime readiness scenario drifted" unless candidate.fetch("scenario") == "security"
    raise "security runtime readiness status drifted" unless candidate.fetch("status") == "not-ready"
    raise "security runtime readiness command drifted" unless candidate.fetch("command") == COMMAND
    raise "security runtime readiness attempt policy drifted" unless candidate.fetch("attempt_policy") == ATTEMPT_POLICY
    raise "security runtime readiness publication policy drifted" unless candidate.fetch("publication_policy") == PUBLICATION_POLICY
    raise "security runtime readiness row_ids drifted" unless candidate.fetch("row_ids") == SecurityScenarioTranche.expected_latest_runtime_row_ids
    raise "security runtime readiness expected outputs drifted" unless candidate.fetch("expected_outputs") == CONTRACT.fetch("expected_outputs")
    raise "security runtime readiness prerequisites drifted" unless candidate.fetch("runtime_prerequisites") == RUNTIME_PREREQUISITES
    raise "security runtime readiness blocked_by drifted" unless candidate.fetch("blocked_by") == CONTRACT.fetch("blocked_by")
    raise "security runtime readiness summary drifted" unless candidate.fetch("summary") == SUMMARY
    raise "security runtime readiness completed/remaining summary drifted" unless plan.fetch("summary").slice(*SUMMARY.keys) == SUMMARY
    completed_ids = plan.fetch("completed_rows").map { |row| SecurityScenarioTranche.row_id_for(row.fetch("pattern_id")) }
    raise "security runtime readiness completed suite binding drifted" unless (candidate.fetch("row_ids") - completed_ids).empty?
    true
  end

  def verify_preflight!(candidate, plan: SecurityScenarioTranche.load_plan, env: ENV.to_h, now: Time.now.utc,
                        pid: Process.pid, repo_root: ROOT, cwd: Dir.pwd)
    verify_contract!(plan: plan)
    raise "security runtime preflight kind drifted" unless candidate.fetch("kind") == PREFLIGHT_KIND
    raise "security runtime preflight schema drifted" unless candidate.fetch("schema_version") == 1
    raise "security runtime preflight tranche drifted" unless candidate.fetch("tranche_id") == TRANCHE_ID
    raise "security runtime preflight scenario drifted" unless candidate.fetch("scenario") == "security"
    raise "security runtime preflight command drifted" unless candidate.fetch("command") == COMMAND
    raise "security runtime preflight attempt policy drifted" unless candidate.fetch("attempt_policy") == ATTEMPT_POLICY
    raise "security runtime preflight publication policy drifted" unless candidate.fetch("publication_policy") == PUBLICATION_POLICY
    raise "security runtime preflight row_ids drifted" unless candidate.fetch("row_ids") == SecurityScenarioTranche.expected_latest_runtime_row_ids
    raise "security runtime preflight expected outputs drifted" unless candidate.fetch("expected_outputs") == CONTRACT.fetch("expected_outputs")
    raise "security runtime preflight prerequisites drifted" unless candidate.fetch("runtime_prerequisites") == RUNTIME_PREREQUISITES
    raise "security runtime preflight repo root drifted" unless candidate.fetch("repo_root") == ROOT && repo_root == ROOT
    raise "security runtime preflight cwd confinement drifted" unless candidate.fetch("cwd") == ROOT && cwd == ROOT
    raise "security runtime preflight pid drifted" unless candidate.fetch("pid") == pid
    raise "security runtime preflight slot env drifted" unless candidate.fetch("slot_token_env") == SLOT_TOKEN_ENV

    failures = preflight_failures(candidate, env: env.to_h, now: now, pid: pid, repo_root: repo_root, cwd: cwd)
    expected_status = failures.empty? ? "ready" : "blocked"
    raise "security runtime preflight status drifted" unless candidate.fetch("status") == expected_status
    raise "security runtime preflight failures drifted" unless candidate.fetch("failures") == failures
    true
  end

  def verify_runnable!(plan: SecurityScenarioTranche.load_plan, preflight: nil, env: ENV.to_h, now: Time.now.utc,
                       pid: Process.pid, repo_root: ROOT, cwd: Dir.pwd, measurements: nil)
    candidate = preflight || evaluate_live_preflight!(
      plan: plan, env: env, now: now, pid: pid, repo_root: repo_root, cwd: cwd, measurements: measurements
    )
    verify_preflight!(candidate, plan: plan, env: env, now: now, pid: pid, repo_root: repo_root, cwd: cwd)
    raise "security runtime readiness is not complete for #{TRANCHE_ID}: #{candidate.fetch('failures').join(', ')}" unless candidate.fetch("status") == "ready"
    candidate
  end

  def current_measurements(repo_root: ROOT)
    {
      "free_gib"=>measure_free_gib(repo_root: repo_root),
      "docker_active_containers"=>measure_docker_active_containers
    }
  end

  def normalize_measurements(measurements)
    {
      "free_gib"=>Float(measurements.fetch("free_gib")),
      "docker_active_containers"=>Integer(measurements.fetch("docker_active_containers"))
    }
  end

  def preflight_failures(candidate, env:, now:, pid:, repo_root:, cwd:)
    failures = []
    failures << "slot-token-missing-or-mismatched" unless valid_slot_token?(candidate.fetch("slot_token"), env.to_h[SLOT_TOKEN_ENV])
    failures << "repo-root-confinement-failed" unless candidate.fetch("repo_root") == ROOT && repo_root == ROOT
    failures << "cwd-confinement-failed" unless candidate.fetch("cwd") == ROOT && cwd == ROOT
    failures << "pid-mismatch" unless candidate.fetch("pid") == pid
    failures << "stale-preflight" unless fresh_preflight?(candidate.fetch("measured_at"), now)
    measurements = normalize_measurements(candidate.fetch("measurements"))
    failures << "insufficient-free-space" unless measurements.fetch("free_gib") >= MINIMUM_FREE_GIB
    failures << "docker-active-containers-not-zero" unless measurements.fetch("docker_active_containers") == 0
    failures << "attempt-policy-drift" unless candidate.fetch("attempt_policy") == ATTEMPT_POLICY
    failures << "expected-outputs-drift" unless candidate.fetch("expected_outputs") == CONTRACT.fetch("expected_outputs")
    failures << "row-ids-drift" unless candidate.fetch("row_ids") == SecurityScenarioTranche.expected_latest_runtime_row_ids
    failures
  end

  def valid_slot_token?(candidate_token, env_token)
    candidate_token.is_a?(String) && !candidate_token.empty? && candidate_token == env_token
  end

  def fresh_preflight?(measured_at, now)
    timestamp = Time.iso8601(measured_at)
    age = now.utc - timestamp.utc
    age >= 0 && age <= MAX_PREFLIGHT_AGE_SECONDS
  rescue ArgumentError
    false
  end

  def measure_free_gib(repo_root: ROOT)
    output, status = Open3.capture2("df", "-k", repo_root)
    raise "security runtime preflight could not inspect disk space" unless status.success?
    lines = output.lines.map(&:strip).reject(&:empty?)
    raise "security runtime preflight missing df output" if lines.length < 2
    available_kib = Integer(lines.last.split(/\s+/)[3])
    (available_kib.to_f / (1024 * 1024)).round(2)
  end

  def measure_docker_active_containers
    output, status = Open3.capture2("docker", "ps", "-q")
    raise "security runtime preflight could not inspect docker containers" unless status.success?
    output.lines.map(&:strip).reject(&:empty?).length
  end
end
