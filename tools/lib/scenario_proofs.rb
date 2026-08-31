# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "yaml"

module ScenarioProofs
  SCENARIOS = %w[normal boundary refusal failure recovery migration operations security performance compatibility].freeze
  POSTGRESQL_SCENARIO = {"refusal"=>"rejection"}.freeze
  GENERATED_AT = "2026-08-28T00:00:00+09:00"
  ROOT = File.expand_path("../..", __dir__)

  module_function

  def sha256(path)
    "sha256:#{Digest::SHA256.file(path).hexdigest}"
  end

  def relative_digest(relative)
    sha256(File.join(ROOT, relative))
  end

  def write_json(relative, document)
    absolute = File.join(ROOT, relative)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, canonical_json(document) + "\n")
    {"path"=>relative, "digest"=>sha256(absolute), "bytes"=>File.size(absolute)}
  end

  def canonical_json(value, indent = 0)
    case value
    when Hash
      return "{}" if value.empty?

      inner = value.map do |key, child|
        "#{' ' * (indent + 2)}#{JSON.generate(key.to_s)}: #{canonical_json(child, indent + 2)}"
      end.join(",\n")
      "{\n#{inner}\n#{' ' * indent}}"
    when Array
      return "[]" if value.empty?

      inner = value.map do |child|
        "#{' ' * (indent + 2)}#{canonical_json(child, indent + 2)}"
      end.join(",\n")
      "[\n#{inner}\n#{' ' * indent}]"
    else
      JSON.generate(value)
    end
  end

  def prepare_integrated_reference
    source_path = "evidence/artifacts/reference-system.json"
    source = JSON.parse(File.read(File.join(ROOT, source_path)))
    raise "Reference System must pass exactly 10 scenarios" unless source.dig("counts", "total") == 10 && source.dig("counts", "passed") == 10
    source_by_scenario = source.fetch("scenario_results").to_h { |row| [row.fetch("scenario"), row] }
    manifest_rows = []
    tests = SCENARIOS.map do |scenario|
      postgresql_scenario = POSTGRESQL_SCENARIO.fetch(scenario, scenario)
      row = source_by_scenario.fetch(postgresql_scenario)
      trace_document = {
        "schema_version"=>1, "scenario"=>scenario, "postgresql_scenario"=>postgresql_scenario,
        "source"=>{"path"=>source_path, "digest"=>relative_digest(source_path)},
        "identity"=>source.fetch("identity"), "oracle"=>row.fetch("oracle"),
        "artifact_pointers"=>row.fetch("artifact_pointers"),
        "streams"=>{
          "action"=>[{"kind"=>"executed-sql-oracle", "path"=>"labs/reference-system/verify.sql"}],
          "network"=>[{"kind"=>"postgresql-client-server-session", "scope"=>"session-observation-not-packet-capture"}],
          "resource"=>row.fetch("artifact_pointers").map { |pointer| {"pointer"=>pointer} }
        },
        "claim_scope"=>"cross-behavior-integrated-scenario-trace"
      }
      observable_document = {
        "schema_version"=>1, "kind"=>"observable-state-artifact-not-visual-screenshot",
        "scenario"=>scenario, "postgresql_scenario"=>postgresql_scenario,
        "final_status"=>row.fetch("final_status"), "oracle"=>row.fetch("oracle"),
        "identity"=>source.fetch("identity"), "claim_scope"=>"cross-behavior-integrated-observation"
      }
      trace = write_json("artifacts/reference-system/traces/#{scenario}.trace.json", trace_document).merge(
        "action_stream"=>true, "network_stream"=>true, "resource_stream"=>true
      )
      screenshot = write_json("artifacts/reference-system/observations/#{scenario}.observable.json", observable_document)
      manifest_rows << {
        "id"=>scenario, "patterns"=>["foundation.reference-system.runtime-slice"],
        "runtime_boundaries"=>["PostgreSQL server", "psql client", "SQL transaction/session"],
        "assertions"=>[JSON.generate(row.fetch("oracle"))]
      }
      {
        "id"=>"reference.#{scenario}", "scenario"=>scenario,
        "title"=>"PostgreSQL integrated #{scenario} (matrix scenario: #{postgresql_scenario})",
        "file"=>"labs/reference-system/verify.sql", "line"=>1,
        "outcome"=>"expected", "attempts"=>1, "final_status"=>row.fetch("final_status"),
        "duration_ms"=>0, "error"=>nil,
        "trace"=>trace, "screenshot"=>screenshot
      }
    end
    write_json("integrations/reference-system/manifest.json", {
      "schema_version"=>1, "id"=>"postgresql-reference-system-v1",
      "status"=>"bounded-integration-proof",
      "subject"=>"PostgreSQL 18.6 integrated SQL runtime scenario system",
      "entry"=>"labs/reference-system/verify.sql",
      "runtime"=>source.dig("identity", "runtime", "container_image"),
      "test"=>"make lab LAB=reference-system",
      "evidence"=>"artifacts/reference-system/results.json",
      "scenarios"=>manifest_rows,
      "completion_limits"=>[
        "Integrated success is not reused as behavior-specific runtime proof.",
        "Authority atomic bindings remain zero and completion eligibility remains false."
      ]
    })
    write_json("artifacts/reference-system/results.json", {
      "schema_version"=>1, "id"=>"postgresql-reference-system-results-v1",
      "created_at"=>GENERATED_AT, "status"=>"passed",
      "command"=>"make lab LAB=reference-system", "profile"=>"container",
      "counts"=>{"total"=>10, "passed"=>10, "failed"=>0, "flaky"=>0, "skipped"=>0},
      "duration_ms"=>source.fetch("duration_ms"),
      "source_digest"=>relative_digest(source_path),
      "harness_digest"=>relative_digest("labs/reference-system/verify.sql"),
      "environment"=>{
        "server_product"=>source.dig("identity", "server", "product"),
        "server_version"=>source.dig("identity", "server", "version"),
        "server_version_num"=>source.dig("identity", "server", "version_num"),
        "client_product"=>source.dig("identity", "client", "product"),
        "client_version"=>source.dig("identity", "client", "version"),
        "contract_version"=>source.dig("identity", "version", "contract"),
        "runtime_container_image"=>source.dig("identity", "runtime", "container_image"),
        "database"=>source.dig("identity", "runtime", "database")
      },
      "trace_contract"=>{
        "per_scenario"=>true, "required_streams"=>%w[action network resource],
        "console_events"=>"PostgreSQL server stderr log is retained separately"
      },
      "tests"=>tests,
      "completion_limits"=>[
        "Integrated traces record PostgreSQL session observations and are not packet captures.",
        "Observable JSON artifacts satisfy the state-capture slot and are not visual screenshots.",
        "Integrated success is not reused as behavior-specific runtime proof.",
        "Authority atomic bindings remain zero and completion eligibility remains false."
      ]
    })
  end

  def json_pointer_escape(value)
    value.to_s.gsub("~", "~0").gsub("/", "~1")
  end

  def matching_pointers(value, matcher, pointer = "")
    case value
    when Hash
      value.flat_map do |key, child|
        child_pointer = "#{pointer}/#{json_pointer_escape(key)}"
        direct = matcher.match?(key.to_s) ? [child_pointer] : []
        direct + matching_pointers(child, matcher, child_pointer)
      end
    when Array
      value.each_with_index.flat_map { |child, index| matching_pointers(child, matcher, "#{pointer}/#{index}") }
    else
      []
    end.uniq
  end

  def load_inputs
    matrix = YAML.safe_load(File.read(File.join(ROOT, "verification.matrix.yaml")), aliases: false)
    coverage = YAML.safe_load(File.read(File.join(ROOT, "coverage.yaml")), aliases: false)
    authority = JSON.parse(File.read(File.join(ROOT, "authority/reviews/decisions.json")))
    reference = JSON.parse(File.read(File.join(ROOT, "evidence/artifacts/reference-system.json")))
    evidences = Dir.glob(File.join(ROOT, "evidence/*.evidence.yaml")).to_h do |path|
      evidence = YAML.safe_load(File.read(path), aliases: false)
      [evidence.fetch("id"), evidence.merge("_manifest_path"=>path.delete_prefix("#{ROOT}/"))]
    end
    [matrix, coverage, authority, reference, evidences]
  end

  def artifact_binding(evidence)
    relative = evidence.dig("artifact", "uri")
    return nil unless relative && File.file?(File.join(ROOT, relative))

    parsed = JSON.parse(File.read(File.join(ROOT, relative))) rescue nil
    {
      "evidence_id"=>evidence.fetch("id"),
      "manifest"=>evidence.fetch("_manifest_path"),
      "path"=>relative,
      "digest"=>relative_digest(relative),
      "media_type"=>evidence.dig("artifact", "media_type"),
      "profile"=>evidence.dig("environment", "profile"),
      "source_digest"=>evidence["source_digest"],
      "harness_digest"=>evidence["harness_digest"],
      "harness_path"=>evidence["harness_path"],
      "command"=>evidence["command"],
      "verdict"=>evidence["verdict"],
      "data"=>parsed
    }
  end

  def observed(category, binding, pointers, extra = {})
    {
      "status"=>"observed",
      "category"=>category,
      "path"=>binding.fetch("path"),
      "digest"=>binding.fetch("digest"),
      "pointers"=>pointers,
      "claim_scope"=>"behavior-scenario-evidence-binding"
    }.merge(extra)
  end

  def gap(category, reason)
    {"status"=>"gap", "category"=>category, "reason"=>reason}
  end

  def sql_binding(evidence, artifact)
    lab = evidence.fetch("id").delete_prefix("lab.")
    path = "labs/#{lab}/verify.sql"
    return gap("sql", "専用SQL HarnessをEvidenceから特定できない。") unless evidence.fetch("id").start_with?("lab.") && File.file?(File.join(ROOT, path))

    {
      "status"=>"observed", "category"=>"sql", "path"=>path,
      "digest"=>relative_digest(path), "result_path"=>artifact.fetch("path"),
      "result_digest"=>artifact.fetch("digest"), "pointers"=>["/"],
      "claim_scope"=>"executed-sql-harness-and-result-for-bounded-behavior-scenario"
    }
  end

  def category_binding(category, artifacts)
    regex = case category
            when "plan" then /(query_?plan|explain|plan_?node|scan_?type)/i
            when "wal" then /(^|_)(wal|lsn)(_|$)/i
            when "metric" then /(calls|latency|duration|elapsed|execution_time|planning_time|throughput|bytes|rows|count|size|hit|miss|ratio|rate|lag)/i
            end
    artifacts.each do |binding|
      next unless binding["data"]
      pointers = matching_pointers(binding.fetch("data"), regex)
      return observed(category, binding, pointers) unless pointers.empty?
    end
    gap(category, "専用#{category.upcase} Artifactまたは機械参照可能なpointerがない。")
  end

  def identity(category, artifacts)
    matcher = case category
              when "server" then /(server_?version|postgres_?version|old_?version|new_?version)/i
              when "client" then /(client_?version|psql_?version|driver_?version)/i
              when "version" then /(server_?version|postgres_?version|old_?version|new_?version|version_?num)/i
              end
    artifacts.each do |binding|
      next unless binding["data"]
      pointers = matching_pointers(binding.fetch("data"), matcher)
      return observed(category, binding, pointers) unless pointers.empty?
    end
    gap(category, "専用Evidenceに#{category} identityが固定されていない。")
  end

  def runtime_identity(artifacts)
    binding = artifacts.first
    return gap("runtime", "専用EvidenceまたはEnvironment profileがない。") unless binding && binding["profile"]

    manifest = "environments/#{binding.fetch("profile")}.yaml"
    return gap("runtime", "Environment manifestが見つからない: #{manifest}") unless File.file?(File.join(ROOT, manifest))

    {
      "status"=>"observed", "category"=>"runtime", "profile"=>binding.fetch("profile"),
      "path"=>manifest, "digest"=>relative_digest(manifest),
      "claim_scope"=>"behavior-scenario-runtime-profile-not-server-or-client-version"
    }
  end

  def build
    matrix, coverage, authority, reference, evidences = load_inputs
    expected_postgresql_scenarios = SCENARIOS.map { |scenario| POSTGRESQL_SCENARIO.fetch(scenario, scenario) }
    raise "Reference System must pass exactly 10 scenarios" unless reference.dig("counts", "total") == 10 && reference.dig("counts", "passed") == 10 && reference.fetch("scenario_results").map { |row| row.fetch("scenario") }.sort == expected_postgresql_scenarios.sort
    raise "Authority decisions must not be machine-promoted" unless authority.fetch("decisions").empty?

    integrated_manifest = JSON.parse(File.read(File.join(ROOT, "integrations/reference-system/manifest.json")))
    integrated_result = JSON.parse(File.read(File.join(ROOT, "artifacts/reference-system/results.json")))
    scenario_runtime_path = "artifacts/pattern-scenarios/results.json"
    scenario_runtime = if File.file?(File.join(ROOT, scenario_runtime_path))
                         JSON.parse(File.read(File.join(ROOT, scenario_runtime_path)))
                       end
    scenario_runtime_records = Array(scenario_runtime && scenario_runtime["tests"])
    manifest_by_scenario = integrated_manifest.fetch("scenarios").to_h { |row| [row.fetch("id"), row] }
    integrated_by_scenario = integrated_result.fetch("tests").to_h { |row| [row.fetch("scenario"), row] }

    rows_by_key = matrix.fetch("rows").to_h { |row| [[row.fetch("behavior_id"), row.fetch("scenario")], row] }
    behaviors = matrix.fetch("rows").map { |row| row.fetch("behavior_id") }.uniq.sort
    target_by_id = coverage.fetch("targets").to_h { |target| [target.fetch("id"), target] }
    reference_by_scenario = reference.fetch("scenario_results").to_h { |row| [row.fetch("scenario"), row] }
    reference_digest = relative_digest("evidence/artifacts/reference-system.json")
    proofs = []

    behaviors.each do |behavior_id|
      target_id = behavior_id.delete_prefix("definitive-domain.")
      target = target_by_id.fetch(target_id)
      SCENARIOS.each do |scenario|
        postgresql_scenario = POSTGRESQL_SCENARIO.fetch(scenario, scenario)
        matrix_row = rows_by_key[[behavior_id, postgresql_scenario]]
        selected_evidence = Array(matrix_row && matrix_row["evidence_ids"]).map { |id| evidences[id] }.compact
        artifact_bindings = selected_evidence.map { |item| artifact_binding(item) }.compact
        sql = if selected_evidence.empty? || artifact_bindings.empty?
                gap("sql", "このBehavior × Scenarioに既存Verification Matrix Evidenceがない。")
              else
                candidates = selected_evidence.zip(selected_evidence.map { |item| artifact_binding(item) }).map { |evidence, artifact| [evidence, artifact] if artifact }.compact
                candidates.map { |evidence, artifact| sql_binding(evidence, artifact) }.find { |item| item.fetch("status") == "observed" } || gap("sql", "既存Evidenceはあるが専用SQL Harnessへ接続されていない。")
              end
        artifacts = {
          "sql"=>sql,
          "plan"=>category_binding("plan", artifact_bindings),
          "wal"=>category_binding("wal", artifact_bindings),
          "log"=>gap("log", "専用Behavior × Scenario Server/Client Log Artifactがない。統合Reference System Logは流用しない。"),
          "metric"=>category_binding("metric", artifact_bindings)
        }
        identities = {
          "server"=>identity("server", artifact_bindings),
          "client"=>identity("client", artifact_bindings),
          "version"=>identity("version", artifact_bindings),
          "runtime"=>runtime_identity(artifact_bindings)
        }
        bounded_supporting_evidence = !matrix_row.nil? && !artifact_bindings.empty?
        all_identity = identities.values.all? { |item| item.fetch("status") == "observed" }
        all_artifacts = artifacts.values.all? { |item| item.fetch("status") == "observed" }
        source_digest_observed = artifact_bindings.any? { |item| item["source_digest"].to_s.match?(/\Asha256:[0-9a-f]{64}\z/) }
        harness_digest_observed = artifact_bindings.any? do |item|
          item["harness_digest"].to_s.match?(/\Asha256:[0-9a-f]{64}\z/) &&
            item["harness_path"] && File.file?(File.join(ROOT, item["harness_path"]))
        end
        oracle_observed = !matrix_row.nil? && !matrix_row["proof_obligation_id"].to_s.empty? &&
          artifact_bindings.any? { |item| item["verdict"] == "pass" }

        runtime_records = scenario_runtime_records.select do |record|
          record["pattern_id"] == behavior_id && record["scenario"] == scenario
        end
        required_variant_ids = ["postgresql-verification-matrix-v2"]
        runtime_variant_ids = runtime_records.map { |record| record["variant_id"] }.sort
        runtime_source_valid = runtime_records.all? do |record|
          record["source_digest"] == relative_digest("verification.matrix.yaml")
        end
        runtime_records_valid = !runtime_records.empty? && runtime_records.all? do |record|
          record["outcome"] == "expected" && record["attempts"] == 1 &&
            record["final_status"] == "passed" && record["error"].nil? &&
            record["oracle"].is_a?(Hash) && !record["oracle"].empty?
        end
        runtime_environment = scenario_runtime && scenario_runtime["environment"]
        runtime_contract_valid = scenario_runtime && scenario_runtime["status"] == "passed" &&
          scenario_runtime.dig("environment", "retries") == 0 &&
          scenario_runtime.dig("environment", "trace_mode") == "on" &&
          scenario_runtime["harness_digest"].to_s.match?(/\Asha256:[0-9a-f]{64}\z/)
        dedicated_runtime_closed = runtime_variant_ids == required_variant_ids &&
          runtime_source_valid && runtime_records_valid && runtime_contract_valid

        # Existing v1 Evidence has useful bounded observations, but it does not record a
        # complete Variant denominator, one dedicated execution per Variant, or an
        # explicit retry_count=0. Those facts must not be inferred from a passing Lab.
        all_variants_executed = dedicated_runtime_closed
        retry_zero = dedicated_runtime_closed
        dedicated_gap_closed = dedicated_runtime_closed
        closure_contract = {
          "surface_scenario_dedicated_row"=>true,
          "bounded_supporting_evidence"=>bounded_supporting_evidence,
          "dedicated_real_server_client"=>dedicated_runtime_closed,
          "variant_denominator_status"=>dedicated_runtime_closed ? "observed" : "gap",
          "all_variants_executed"=>all_variants_executed,
          "retry_count"=>{"status"=>dedicated_runtime_closed ? "observed" : "gap", "value"=>dedicated_runtime_closed ? 0 : nil, "required"=>0},
          "oracle"=>{"status"=>dedicated_runtime_closed || oracle_observed ? "observed" : "gap", "proof_obligation_id"=>matrix_row && matrix_row["proof_obligation_id"]},
          "source_digest"=>{"status"=>dedicated_runtime_closed || source_digest_observed ? "observed" : "gap"},
          "harness_digest"=>{"status"=>dedicated_runtime_closed || harness_digest_observed ? "observed" : "gap"},
          "required_artifacts"=>%w[sql plan wal log metric].to_h { |category| [category, dedicated_runtime_closed ? "observed" : artifacts.fetch(category).fetch("status")] },
          "integrated_reference_credit"=>false,
          "foreign_artifact_metadata_credit"=>false,
          "gap_closed"=>dedicated_gap_closed
        }
        proof = {
          "schema_version"=>1,
          "id"=>"proof.behavior.#{target_id}.#{scenario}",
          "atlas_id"=>"postgresql-reference-atlas",
          "generated_at"=>GENERATED_AT,
          "behavior_scope"=>"current-domain-pattern-not-authority-atomic",
          "behavior_id"=>behavior_id,
          "pattern_id"=>behavior_id,
          "target_id"=>target_id,
          "target_set"=>target.fetch("target_set"),
          "scenario"=>scenario,
          "status"=>dedicated_gap_closed ? "bounded-runtime-proof" : "pattern-specific-gap",
          "classification"=>{
            "method"=>"postgresql-verification-matrix-row-or-explicit-gap",
            "matcher_digest"=>relative_digest("verification.matrix.yaml"),
            "state_ids"=>[postgresql_scenario], "semantic_scope_match"=>!matrix_row.nil?
          },
          "source_bindings"=>[{
            "variant_id"=>"postgresql-verification-matrix-v2",
            "path"=>"verification.matrix.yaml", "digest"=>relative_digest("verification.matrix.yaml")
          }],
          "pattern_evidence"=>{
            "capture_environment_identity"=>{
              "postgresql_scenario"=>postgresql_scenario,
              "server"=>identities.fetch("server"), "client"=>identities.fetch("client"),
              "version"=>identities.fetch("version"), "runtime"=>identities.fetch("runtime"),
              "closure_contract"=>closure_contract
            },
            "capture_harness_digest"=>relative_digest("verification.matrix.yaml"),
            "capture_records"=>artifacts.values,
            "benchmark_environment"=>nil, "benchmark_records"=>[],
            "compatibility_environment"=>nil, "compatibility_records"=>[]
          }.merge(dedicated_runtime_closed ? {
            "scenario_runtime_report"=>scenario_runtime_path,
            "scenario_runtime_environment"=>runtime_environment,
            "scenario_runtime_records"=>runtime_records
          } : {}),
          "integrated_reference"=>{
            "manifest"=>"integrations/reference-system/manifest.json",
            "result"=>"artifacts/reference-system/results.json",
            "runtime_boundaries"=>manifest_by_scenario.fetch(scenario).fetch("runtime_boundaries"),
            "assertions"=>manifest_by_scenario.fetch(scenario).fetch("assertions"),
            "outcome"=>integrated_by_scenario.fetch(scenario).fetch("outcome"),
            "attempts"=>integrated_by_scenario.fetch(scenario).fetch("attempts"),
            "trace"=>integrated_by_scenario.fetch(scenario).fetch("trace"),
            "screenshot"=>integrated_by_scenario.fetch(scenario).fetch("screenshot"),
            "pattern_mapped"=>false
          },
          "closure"=>{
            "dedicated_row"=>true,
            "dedicated_artifact"=>true,
            "pattern_specific_evidence"=>dedicated_gap_closed,
            "real_runtime_identity"=>dedicated_gap_closed,
            "integrated_runtime_trace"=>true,
            "authority_atomic_behavior"=>false,
            "completion_eligible"=>false
          },
          "gaps"=>[
            ("既存Verification MatrixにこのBehavior × Scenario専用rowがない。" unless matrix_row),
            ("専用Evidence Artifactがない。" if !dedicated_runtime_closed && artifact_bindings.empty?),
            ("全Variantのstable denominatorと専用実行記録がない。" unless dedicated_runtime_closed),
            ("専用実行のretry count 0を機械記録していない。" unless dedicated_runtime_closed),
            ("専用Oracleと期待結果の対応がない。" unless dedicated_runtime_closed || oracle_observed),
            ("専用Source digestがない。" unless dedicated_runtime_closed || source_digest_observed),
            ("専用Harness digestまたはHarness pathがない。" unless dedicated_runtime_closed || harness_digest_observed),
            *identities.map { |name, item| "#{name} identity gap: #{item.fetch("reason")}" if !dedicated_runtime_closed && item.fetch("status") == "gap" }.compact,
            *artifacts.map { |name, item| "#{name} artifact gap: #{item.fetch("reason")}" if !dedicated_runtime_closed && item.fetch("status") == "gap" }.compact,
            "統合Reference Systemの結果は専用Surface × Scenario × Variant Closureへ流用しない。",
            "別Evidence Artifactのmetadataだけでは専用実行Proofを閉じない。",
            "Authority raw anchorのHuman reviewとAtomic behavior bindingが未完了でCompletion対象外。"
          ].compact
        }
        proofs << proof
      end
    end
    [proofs, behaviors]
  end
end
