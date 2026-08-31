# frozen_string_literal: true

require "json"

module SecurityScenarioTranche
  ROOT = File.expand_path("../..", __dir__)
  PLAN_PATH = File.join(ROOT, "evidence/scenarios/closure-plan.json")
  BASELINE_PATTERN_IDS = %w[
    definitive-domain.concurrency.deadlock
    definitive-domain.concurrency.locking
    definitive-domain.concurrency.mvcc
    definitive-domain.foundation.authority-lock
    definitive-domain.foundation.version-lock
    definitive-domain.lifecycle.compatibility-matrix
    definitive-domain.lifecycle.pg-upgrade
    definitive-domain.lifecycle.schema-migration
    definitive-domain.lifecycle.upgrade
    definitive-domain.operations.backup-recovery
    definitive-domain.operations.failure-injection
    definitive-domain.operations.logical-replication
    definitive-domain.operations.maintenance
    definitive-domain.operations.observability
    definitive-domain.operations.pitr-recovery
    definitive-domain.operations.replication
  ].freeze
  COMPLETED_PATTERN_IDS = BASELINE_PATTERN_IDS + %w[
    definitive-domain.operations.wal
    definitive-domain.performance.execution
    definitive-domain.performance.index
    definitive-domain.performance.planner
    definitive-domain.performance.statistics
    definitive-domain.publication.provenance
    definitive-domain.query.catalog-inventory
    definitive-domain.query.extension
  ].freeze
  PUBLISHED_TRANCHE_PATTERN_IDS = %w[
    definitive-domain.performance.statistics
    definitive-domain.publication.provenance
    definitive-domain.query.catalog-inventory
    definitive-domain.query.extension
  ].freeze
  NEXT_TRANCHE_PATTERN_IDS = %w[
    definitive-domain.query.partitioning
    definitive-domain.query.security
    definitive-domain.query.sql-surface
    definitive-domain.query.types-constraints
  ].freeze
  FOLLOWING_TRANCHE_ID = "security-002"
  FOLLOWING_TRANCHE_PATTERN_IDS = %w[
    definitive-domain.skill.router-evaluation
  ].freeze
  MAX_PATTERN_ROWS = 4

  module_function

  def load_plan
    JSON.parse(File.read(PLAN_PATH))
  end

  def row_id_for(pattern_id)
    "closure.#{pattern_id}.security"
  end

  def expected_row_ids
    NEXT_TRANCHE_PATTERN_IDS.map { |pattern_id| row_id_for(pattern_id) }
  end

  def expected_published_row_ids
    PUBLISHED_TRANCHE_PATTERN_IDS.map { |pattern_id| row_id_for(pattern_id) }
  end

  def expected_following_row_ids
    FOLLOWING_TRANCHE_PATTERN_IDS.map { |pattern_id| row_id_for(pattern_id) }
  end

  def completed_row_ids
    COMPLETED_PATTERN_IDS.map { |pattern_id| row_id_for(pattern_id) }
  end

  def verify_completed_suite!(plan = load_plan)
    completed = Array(plan.fetch("completed_rows"))
    raise "security completed suite cardinality drifted" unless completed.length == COMPLETED_PATTERN_IDS.length
    raise "security completed suite pattern_ids drifted from the approved order" unless completed.map { |row| row.fetch("pattern_id") } == COMPLETED_PATTERN_IDS
    raise "security completed suite scenario drifted" unless completed.all? { |row| row.fetch("scenario") == "security" }
    completed
  end

  def verify_next_tranche!(plan = load_plan)
    tranche = plan.fetch("next_tranche")
    raise "security tranche must remain planned" unless tranche.fetch("status") == "planned"
    raise "security tranche must stay on risk rank 1" unless tranche.fetch("risk_rank") == 1
    raise "security tranche must remain the next security tranche" unless tranche.fetch("id") == "security-001" && tranche.fetch("scenario") == "security"
    raise "security tranche must stay within 4 pattern rows" unless tranche.fetch("row_ids").length <= MAX_PATTERN_ROWS && tranche.fetch("pattern_rows") <= MAX_PATTERN_ROWS
    raise "security tranche row_ids drifted from the approved order" unless tranche.fetch("row_ids") == expected_row_ids
    raise "security tranche variant denominator drifted" unless tranche.fetch("variant_runs") == tranche.fetch("row_ids").length
    tranche
  end

  def runtime_pattern_ids(plan = load_plan)
    next_runtime_pattern_ids(plan)
  end

  def published_pattern_ids(plan = load_plan)
    verify_completed_suite!(plan)
    COMPLETED_PATTERN_IDS
  end

  def next_runtime_pattern_ids(plan = load_plan)
    verify_completed_suite!(plan)
    verify_next_tranche!(plan)
    COMPLETED_PATTERN_IDS + NEXT_TRANCHE_PATTERN_IDS
  end

  def verify_following_tranche!(plan = load_plan)
    security_tranches = plan.fetch("tranches").select { |tranche| tranche.fetch("scenario") == "security" }
    tranche = security_tranches.fetch(1)
    raise "following security tranche identity drifted" unless tranche.fetch("id") == FOLLOWING_TRANCHE_ID
    raise "following security tranche row_ids drifted from the approved order" unless tranche.fetch("row_ids") == expected_following_row_ids
    raise "following security tranche must stay within 4 pattern rows" unless tranche.fetch("row_ids").length <= MAX_PATTERN_ROWS && tranche.fetch("pattern_rows") <= MAX_PATTERN_ROWS
    raise "following security tranche variant denominator drifted" unless tranche.fetch("variant_runs") == tranche.fetch("row_ids").length
    tranche
  end
end
