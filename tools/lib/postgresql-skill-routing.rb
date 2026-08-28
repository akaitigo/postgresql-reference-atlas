# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "time"
require "yaml"

module PostgreSQLSkillRouting
  GENERATED_AT = "2026-08-28T00:00:00+09:00"
  OUTCOME_CONTRACTS = {
    "understand"=>{"mode"=>"review", "mutation_policy"=>"read-only", "required_output_fields"=>%w[principle boundary version coverage-state evidence]},
    "choose"=>{"mode"=>"design", "mutation_policy"=>"read-only", "required_output_fields"=>%w[primary-candidate alternatives tradeoffs constraints coverage-state]},
    "build"=>{"mode"=>"implement", "mutation_policy"=>"explicit-authorization-required", "required_output_fields"=>%w[target variant constraints authorized-change-scope verification]},
    "verify"=>{"mode"=>"review", "mutation_policy"=>"read-only", "required_output_fields"=>%w[oracle reproduction-command evidence environment coverage-state]},
    "operate"=>{"mode"=>"diagnose", "mutation_policy"=>"read-only", "required_output_fields"=>%w[telemetry degradation runbook recovery evidence]},
    "troubleshoot"=>{"mode"=>"diagnose", "mutation_policy"=>"read-only", "required_output_fields"=>%w[reproduction failure-stage cause recovery-condition evidence]},
    "evolve"=>{"mode"=>"migrate", "mutation_policy"=>"explicit-authorization-required", "required_output_fields"=>%w[old-new-mapping compatibility migration-evidence non-regression rollback]},
    "delegate"=>{"mode"=>"review", "mutation_policy"=>"explicit-authorization-required", "required_output_fields"=>%w[target variant constraints authorized-change-scope stop-condition review]}
  }.freeze
  STOP_CONDITIONS = %w[
    coverage-gap unverified-evidence unauthorized-mutation external-human-decision-required
    stale-source-relock-explicit-procedure-required ambiguous-or-unknown-query
  ].freeze

  PROFILES = {
    "orientation-scope"=>{
      "query"=>"PostgreSQL 18.6の対象範囲と一次資料境界",
      "targets"=>%w[foundation.version-lock foundation.authority-lock],
      "variants"=>[["docs-lock", "sources.lock.yaml"], ["source-lock", "authority/extraction.snapshot.json"]]
    },
    "foundations-mechanics"=>{
      "query"=>"MVCC snapshotとWAL durabilityの内部機構",
      "targets"=>%w[concurrency.mvcc operations.wal query.sql-surface foundation.reference-system],
      "variants"=>[["mvcc-snapshot", "evidence/artifacts/mvcc.json"], ["wal-redo", "evidence/artifacts/wal.json"]]
    },
    "architecture-design"=>{
      "query"=>"Schema Transaction Clusterの統合Architecture",
      "targets"=>%w[foundation.reference-system query.partitioning concurrency.locking performance.planner operations.replication lifecycle.schema-migration],
      "variants"=>[["integrated-runtime", "evidence/artifacts/reference-system.json"], ["replicated-runtime", "evidence/artifacts/replication.json"]]
    },
    "implementation-construction"=>{
      "query"=>"SQL ConstraintとExtensionを隔離環境へ構築",
      "targets"=>%w[query.sql-surface query.extension concurrency.mvcc performance.index operations.replication lifecycle.schema-migration],
      "variants"=>[["sql-schema", "labs/sql/verify.sql"], ["extension-module", "labs/extension/verify.sql"]]
    },
    "testing-verification"=>{
      "query"=>"Query Plan SQLSTATE WAL runtime Evidenceを検証",
      "targets"=>%w[query.sql-surface concurrency.deadlock performance.planner operations.failure-injection lifecycle.compatibility-matrix],
      "variants"=>[["normal-oracle", "evidence/artifacts/reference-system.json"], ["failure-oracle", "evidence/artifacts/failure-injection.json"]]
    },
    "failure-recovery"=>{
      "query"=>"Backend障害とPITR recoveryを診断",
      "targets"=>%w[concurrency.deadlock operations.failure-injection operations.pitr-recovery lifecycle.upgrade],
      "variants"=>[["transaction-recovery", "evidence/artifacts/failure-injection.json"], ["point-in-time-recovery", "evidence/artifacts/pitr.json"]]
    },
    "operations-observability"=>{
      "query"=>"pg_statとVACUUMで運用状態を観測",
      "targets"=>%w[performance.execution operations.observability operations.maintenance],
      "variants"=>[["runtime-observability", "evidence/artifacts/observability.json"], ["maintenance-observability", "evidence/artifacts/maintenance.json"]]
    },
    "security-privacy-safety"=>{
      "query"=>"RLS SCRAM privilegeの拒否境界を検証",
      "targets"=>%w[query.security security.authorization concurrency.locking operations.runbook-exercises foundation.authority-lock],
      "variants"=>[["row-level-security", "evidence/artifacts/security.json"], ["authorization-boundary", "operations/security.md"]]
    },
    "performance-capacity-cost"=>{
      "query"=>"EXPLAIN query planとIndex容量を比較",
      "targets"=>%w[performance.planner performance.index performance.execution operations.observability],
      "variants"=>[["planner-plan", "evidence/artifacts/planner.json"], ["index-access", "evidence/artifacts/index.json"]]
    },
    "compatibility-integration"=>{
      "query"=>"14.24から18.6のClient Protocol Extension互換性",
      "targets"=>%w[lifecycle.compatibility-matrix integration.client-tools query.extension foundation.version-lock],
      "variants"=>[["version-matrix", "evidence/artifacts/compatibility-matrix.json"], ["extension-runtime", "evidence/artifacts/extension.json"]]
    },
    "migration-evolution-deprecation"=>{
      "query"=>"Schema migrationとpg_upgradeを非後退で移行",
      "targets"=>%w[lifecycle.schema-migration lifecycle.pg-upgrade lifecycle.upgrade-matrix],
      "variants"=>[["online-schema-migration", "evidence/artifacts/migration.json"], ["binary-major-upgrade", "evidence/artifacts/pg-upgrade.json"]]
    },
    "decision-comparison"=>{
      "query"=>"Index Partition Backup方式を同じ条件で比較",
      "targets"=>%w[query.partitioning concurrency.transactions-isolation performance.index operations.backup-methods lifecycle.upgrade-matrix],
      "variants"=>[["index-alternative", "evidence/artifacts/index.json"], ["partition-alternative", "evidence/artifacts/partitioning.json"]]
    },
    "provenance-rights"=>{
      "query"=>"一次資料Digest License Evidence来歴を監査",
      "targets"=>%w[publication.provenance foundation.authority-lock],
      "variants"=>[["source-provenance", "sources.lock.yaml"], ["rights-manifest", "third_party/manifest.yaml"]]
    },
    "agent-skill"=>{
      "query"=>"Agent routingとEvidence bindingを評価",
      "targets"=>%w[skill.definitive-proof-routing skill.router-evaluation],
      "variants"=>[["legacy-router", ".agents/skills/postgresql-atlas/scripts/route.sh"], ["definitive-planner", ".agents/skills/postgresql-atlas/scripts/plan-request.rb"]]
    }
  }.freeze

  DOMAIN_PATTERNS = {
    "sql"=>/\b(sql|constraint|type|extension|partition)\b|制約|型|拡張|パーティション/i,
    "concurrency"=>/\b(mvcc|lock|deadlock|transaction|isolation)\b|ロック|トランザクション/i,
    "planner"=>/\b(planner|explain|index|statistics|performance)\b|実行計画|索引|性能/i,
    "wal"=>/\b(wal|checkpoint|backup|pitr|replication|recovery)\b|バックアップ|復旧|レプリケーション/i,
    "security"=>/\b(rls|scram|security|privilege|auth)\b|権限|認証|セキュリティ/i,
    "lifecycle"=>/\b(upgrade|migration|compatibility|deprecation)\b|移行|互換|アップグレード/i,
    "authority"=>/\b(authority|source|provenance|license|scope)\b|一次資料|来歴|対象範囲/i,
    "skill"=>/\b(agent|skill|routing|delegate)\b|委任|ルーティング/i
  }.freeze

  module_function

  def sha256(bytes)
    "sha256:#{Digest::SHA256.hexdigest(bytes)}"
  end

  def binding(root, relative, extra = {})
    bytes = File.binread(File.join(root, relative))
    {"path"=>relative, "digest"=>sha256(bytes), "bytes"=>bytes.bytesize}.merge(extra)
  end

  def context(root)
    mastery = YAML.safe_load(File.read(File.join(root, "mastery.yaml")), aliases: false)
    coverage = YAML.safe_load(File.read(File.join(root, "coverage.yaml")), aliases: false)
    claims = YAML.safe_load(File.read(File.join(root, "atlas/claims/index.yaml")), aliases: false).fetch("claims").to_h { |claim| [claim.fetch("id"), claim] }
    sources = YAML.safe_load(File.read(File.join(root, "sources.lock.yaml")), aliases: false).fetch("sources").to_h { |source| [source.fetch("id"), source] }
    evidence = Dir.glob(File.join(root, "evidence/*.evidence.yaml")).to_h do |path|
      item = YAML.safe_load(File.read(path), aliases: false)
      [item.fetch("id"), [path.delete_prefix("#{root}/"), item]]
    end
    {"mastery"=>mastery, "targets"=>coverage.fetch("targets"), "target_by_id"=>coverage.fetch("targets").to_h { |target| [target.fetch("id"), target] }, "claims"=>claims, "sources"=>sources, "evidence"=>evidence}
  end

  def query_boundary(query)
    hits = DOMAIN_PATTERNS.each_with_object([]) { |(id, pattern), result| result << id if query.match?(pattern) }
    return ["unknown-query", hits] if hits.empty?
    return ["ambiguous-query", hits] if hits.length > 1
    [nil, hits]
  end

  def authority_bindings(ctx, target)
    source_ids = target.fetch("claim_ids", []).flat_map { |id| ctx.fetch("claims").fetch(id, {}).fetch("source_ids", []) }.uniq
    source_ids = ["postgresql-docs-18.6"] if source_ids.empty?
    source_ids.sort.map do |id|
      source = ctx.fetch("sources").fetch(id)
      source.slice("id", "url", "version", "digest").merge("binding_scope"=>(target.fetch("claim_ids", []).empty? ? "subject-version-authority-not-target-specific" : "target-claim-authority"))
    end
  end

  def evidence_bindings(root, ctx, target)
    target.fetch("evidence_ids", []).each_with_object([]) do |id, result|
      pair = ctx.fetch("evidence")[id]
      next unless pair
      manifest_path, item = pair
      artifact_path = item.dig("artifact", "uri")
      result << binding(root, manifest_path, "id"=>id, "binding_kind"=>"evidence-manifest", "verdict"=>item.fetch("verdict"))
      result << binding(root, artifact_path, "id"=>id, "binding_kind"=>"runtime-artifact", "claim_scope"=>"target-bounded-proof")
    end
  end

  def choose_target(ctx, outcome, surface, profile)
    allowed_sets = outcome.fetch("target_sets") & surface.fetch("target_sets")
    candidates = profile.fetch("targets").map { |id| ctx.fetch("target_by_id").fetch(id) }
    [candidates.find { |target| allowed_sets.include?(target.fetch("target_set")) } || candidates.first, allowed_sets]
  end

  def plan(root, request, ctx = context(root))
    outcome = ctx.fetch("mastery").fetch("outcomes").find { |item| item.fetch("id") == request.fetch("outcome") } or abort "Unknown Outcome"
    surface = ctx.fetch("mastery").fetch("surfaces").find { |item| item.fetch("id") == request.fetch("surface") } or abort "Unknown Surface"
    profile = PROFILES.fetch(surface.fetch("id"))
    execution = OUTCOME_CONTRACTS.fetch(outcome.fetch("id"))
    query = request.fetch("query", profile.fetch("query"))
    query_error, query_domains = query_boundary(query)
    query_error = nil if request["structured_route"] == true
    target, allowed_sets = choose_target(ctx, outcome, surface, profile)
    target_allowed = allowed_sets.include?(target.fetch("target_set"))
    evidence = evidence_bindings(root, ctx, target)
    disposition = if query_error
                    "coverage-gap"
                  elsif !target_allowed
                    "mastery-routing-gap"
                  elsif target.fetch("state") == "covered" && evidence.any?
                    "bounded-evidence-route"
                  else
                    "coverage-gap"
                  end
    blocked = []
    blocked << "ambiguous-or-unknown-query" if query_error
    blocked << "unauthorized-mutation" if execution.fetch("mutation_policy") == "explicit-authorization-required" && request["authorized_change"] != true
    blocked << "external-human-decision-required" if request["authority_semantic_decision"] == true
    blocked << "stale-source-relock-explicit-procedure-required" if request["stale_source_relock"] == true
    status = blocked.any? ? "blocked" : disposition
    variants = profile.fetch("variants").map { |id, path| binding(root, path, "id"=>id, "claim_scope"=>"route-candidate-not-target-completion-proof") }
    runtime = JSON.parse(File.read(File.join(root, "evidence/artifacts/reference-system.json")))
    {
      "id"=>request.fetch("id"), "status"=>status, "outcome"=>outcome.fetch("id"), "surface"=>surface.fetch("id"),
      "query"=>query, "query_domains"=>query_domains, "query_boundary"=>(query_error || "recognized-single-domain"),
      "mode"=>execution.fetch("mode"), "target_id"=>target.fetch("id"), "target_set"=>target.fetch("target_set"),
      "target_set_allowed"=>target_allowed, "coverage_state"=>target.fetch("state"), "coverage_disposition"=>disposition,
      "routing_gap_reasons"=>[(!target_allowed ? "outcome-surface-target-set-disjoint" : nil), (target.fetch("state") != "covered" ? "target-state-#{target.fetch('state')}" : nil), (evidence.empty? ? "target-has-no-executable-evidence" : nil)].compact,
      "required_deliverables"=>surface.fetch("required_deliverables"), "required_output_fields"=>execution.fetch("required_output_fields"),
      "mutation_policy"=>execution.fetch("mutation_policy"),
      "mutation_status"=>(execution.fetch("mutation_policy") == "read-only" ? "read-only" : request["authorized_change"] == true && blocked.empty? ? "authorized-for-request-scope" : "blocked"),
      "blocked_reasons"=>blocked, "stop_conditions"=>STOP_CONDITIONS,
      "variant_bindings"=>variants, "authority_bindings"=>authority_bindings(ctx, target), "evidence_bindings"=>evidence,
      "runtime_integration_binding"=>binding(root, "evidence/artifacts/reference-system.json", "server_version"=>runtime.fetch("server_version"), "query_plan_pointer"=>"/query_plan", "wal_pointer"=>"/wal_bytes_delta", "claim_scope"=>"shared-integration-slice-not-target-completion-proof")
    }
  end

  def matrix_requests(ctx)
    ctx.fetch("mastery").fetch("outcomes").flat_map do |outcome|
      ctx.fetch("mastery").fetch("surfaces").map do |surface|
        execution = OUTCOME_CONTRACTS.fetch(outcome.fetch("id"))
        {"id"=>"skill.#{outcome.fetch('id')}.#{surface.fetch('id')}", "outcome"=>outcome.fetch("id"), "surface"=>surface.fetch("id"), "query"=>PROFILES.fetch(surface.fetch("id")).fetch("query"), "structured_route"=>true, "authorized_change"=>execution.fetch("mutation_policy") == "explicit-authorization-required"}
      end
    end
  end

  def evaluate_plan(root, plan, request, ctx)
    target = ctx.fetch("target_by_id").fetch(plan.fetch("target_id"))
    execution = OUTCOME_CONTRACTS.fetch(plan.fetch("outcome"))
    expected_disposition = if !plan.fetch("target_set_allowed")
                             "mastery-routing-gap"
                           elsif target.fetch("state") == "covered" && target.fetch("evidence_ids", []).any?
                             "bounded-evidence-route"
                           else
                             "coverage-gap"
                           end
    assertions = {
      "identity"=>plan.fetch("id") == request.fetch("id") && plan.fetch("outcome") == request.fetch("outcome") && plan.fetch("surface") == request.fetch("surface"),
      "recognized_structured_query"=>plan.fetch("query_boundary") == "recognized-single-domain" && plan.fetch("blocked_reasons").empty?,
      "target_state_honesty"=>plan.fetch("coverage_state") == target.fetch("state") && plan.fetch("coverage_disposition") == expected_disposition,
      "mutation_authorization"=>plan.fetch("mutation_policy") == execution.fetch("mutation_policy") && plan.fetch("mutation_status") == (execution.fetch("mutation_policy") == "read-only" ? "read-only" : "authorized-for-request-scope"),
      "variant_binding"=>plan.fetch("variant_bindings").length >= 2 && plan.fetch("variant_bindings").all? { |binding| File.file?(File.join(root, binding.fetch("path"))) && binding.fetch("digest").match?(/\Asha256:[a-f0-9]{64}\z/) },
      "authority_binding"=>plan.fetch("authority_bindings").any? && plan.fetch("authority_bindings").all? { |binding| binding.fetch("url").start_with?("https://") && binding.fetch("digest").match?(/\Asha256:[a-f0-9]{64}\z/) },
      "target_evidence_binding"=>(target.fetch("evidence_ids", []).empty? ? plan.fetch("evidence_bindings").empty? : plan.fetch("evidence_bindings").any?),
      "runtime_query_plan_wal_binding"=>plan.dig("runtime_integration_binding", "server_version") == "18.6" && plan.dig("runtime_integration_binding", "query_plan_pointer") == "/query_plan" && plan.dig("runtime_integration_binding", "wal_pointer") == "/wal_bytes_delta" && plan.dig("runtime_integration_binding", "claim_scope") == "shared-integration-slice-not-target-completion-proof",
      "stop_conditions"=>%w[coverage-gap unauthorized-mutation external-human-decision-required stale-source-relock-explicit-procedure-required ambiguous-or-unknown-query].all? { |condition| plan.fetch("stop_conditions").include?(condition) }
    }
    plan.merge("contract_assertions"=>assertions, "contract_result"=>(assertions.values.all? ? "pass" : "fail"))
  end
end
