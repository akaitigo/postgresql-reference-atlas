# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "yaml"

module EvidenceDependencyGraph
  ROOT = File.expand_path("../..", __dir__)
  GRAPH_PATH = "evidence/dependency-graph.json"
  LEDGER_PATH = "evidence/dependency-rerun.json"
  POLICY = {
    "transitive_staleness"=>true,
    "digest_only_closure_forbidden"=>true,
    "actual_rerun_required"=>true,
    "missing_rerun_targets_fail"=>true,
    "proof_structure_invariant"=>true,
    "closure_plan_structure_invariant"=>true
  }.freeze

  module_function

  def absolute(relative)
    File.join(ROOT, relative)
  end

  def relative(path)
    path.delete_prefix("#{ROOT}/")
  end

  def digest_file(relative_path)
    "sha256:#{Digest::SHA256.file(absolute(relative_path)).hexdigest}"
  end

  def canonical(value)
    case value
    when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def digest_canonical(value)
    "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonical(value)))}"
  end

  def files(*patterns)
    patterns.flat_map { |pattern| Dir.glob(absolute(pattern)) }
      .select { |path| File.file?(path) }
      .map { |path| relative(path) }.uniq.sort
  end

  def input_specs
    evidence_dependency_control_plane_members = %w[
      tools/generate-evidence-dependency-graph.rb
      tools/lib/evidence_dependency_graph.rb
      tools/lib/tracked_generated_freshness.rb
      tools/verify-generated-output-readonly.rb
      tools/verify-tracked-generated-freshness.rb
      tools/test-readonly-generator-command-baseline.rb
      tools/test-tracked-generated-freshness.rb
      tests/evidence-dependency-inputs.rb
      tests/evidence-pipeline-clean.rb
      tests/query-sql-commands-partial-contract.rb
      tests/security-query-catalog-inventory-contract.rb
      tests/security-query-extension-contract.rb
      tests/security-publication-provenance-contract.rb
      tests/security-performance-statistics-contract.rb
      tests/security-published-tranche-contract.rb
      tests/security-next-tranche-contract.rb
      tests/security-runtime-readiness-contract.rb
    ].freeze
    legacy_scenario_skill_reporting_members = files(
      "tools/**/*.rb", "evals/run.sh", "evals/cases.json", ".agents/skills/postgresql-atlas/**/*"
    )
    scenario_reporting_required_members = %w[
      tools/lib/security_query_catalog_inventory_contract.rb
      tools/lib/security_query_extension_contract.rb
      tools/lib/security_publication_provenance_contract.rb
      tools/lib/security_performance_statistics_contract.rb
      tools/lib/security_published_tranche_contract.rb
      tools/lib/security_runtime_readiness_contract.rb
      tools/lib/security_scenario_tranche.rb
      tools/lib/security_next_tranche_contract.rb
    ].freeze
    specs = [
      ["source.contract-and-authority", "source", %w[
        atlas.yaml mastery.yaml sources.lock.yaml coverage.yaml skill.package.yaml
        definitive.yaml surface.inventory.yaml verification.matrix.yaml depth.parity.yaml
        third_party/manifest.yaml
      ] + files("surface/**/*.yaml", "atlas/**/*.yaml")],
      ["harness.sql-schema-correctness", "harness", files(
        "labs/{authority-lock,definitive-inventory,sql-surface,sql,types-constraints,catalog-inventory,partitioning,extension,security,index,planner,statistics}/**/*",
        "scripts/{lib.sh,run-lab.sh,run-sql-lab.sh}"
      )],
      ["harness.concurrency-mvcc", "harness", files("labs/{mvcc,locking,deadlock}/**/*", "scripts/{lib.sh,run-lab.sh,run-sql-lab.sh}")],
      ["harness.wal-replication-backup", "harness", files(
        "labs/{wal,backup-recovery,pitr,replication,logical-replication}/**/*",
        "scripts/{lib.sh,run-lab.sh,run-sql-lab.sh}"
      )],
      ["harness.migration-compatibility", "harness", files(
        "labs/{migration,upgrade,pg-upgrade,compatibility-matrix}/**/*",
        "scripts/{lib.sh,run-lab.sh,run-sql-lab.sh}"
      )],
      ["harness.operations-performance-recovery", "harness", files(
        "labs/{performance,observability,maintenance,failure-injection,reference-system}/**/*",
        "scripts/{lib.sh,run-lab.sh,run-sql-lab.sh,static-gates.sh,graph-gates.rb}"
      )],
      ["harness.scenario-skill-reporting", "harness", (legacy_scenario_skill_reporting_members - evidence_dependency_control_plane_members + scenario_reporting_required_members).uniq.sort],
      ["harness.evidence-dependency-control-plane", "harness", evidence_dependency_control_plane_members],
      ["runtime.postgresql-server-client", "runtime", %w[sources.lock.yaml go.mod scripts/lib.sh]],
      ["profile.local", "profile", %w[environments/local.yaml]],
      ["profile.container", "profile", %w[environments/container.yaml]],
      ["profile.cluster", "profile", %w[environments/cluster.yaml]]
    ]
    specs.map do |id, kind, members|
      missing = members.reject { |path| File.file?(absolute(path)) }
      raise "Dependency input #{id} のmemberがありません: #{missing.join(', ')}" unless missing.empty?
      raise "Dependency input #{id} が空です" if members.empty?
      {"id"=>id, "kind"=>kind, "members"=>members.uniq.sort}
    end
  end

  def aggregate_member_digest(members)
    digest_canonical(members.sort.map { |path| {"path"=>path, "digest"=>digest_file(path)} })
  end

  def current_input_bindings
    input_specs.map do |spec|
      spec.merge("digest"=>aggregate_member_digest(spec.fetch("members")))
    end
  end

  def definitive_paths
    doc = YAML.safe_load(File.read(absolute("definitive.yaml")), aliases: false)
    %w[scenario_proofs scenario_closure_plan evidence_durability skill_eval skill_router]
      .map { |key| doc[key] if doc[key] && File.file?(absolute(doc[key])) }.compact
  end

  # Mirrors Core's mechanical denominator, then adds PostgreSQL-specific runtime
  # artifacts and harness manifests. Every discovered path is required.
  def required_output_paths
    paths = []
    %w[
      artifacts/e2e-results.json artifacts/e2e-results.container.json artifacts/capture-manifest.json
      artifacts/capture-results.json artifacts/benchmark-results.json artifacts/compatibility-results.json
      artifacts/reference-system/results.json artifacts/pattern-scenarios/results.json
      evidence/scenarios/index.json evidence/scenarios/closure-plan.json provenance.yaml
    ].each { |path| paths << path if File.file?(absolute(path)) }
    paths.concat files("artifacts/**/*.{json,yaml,yml}").select { |path| File.basename(path).downcase.match?(/results|manifest/) }
    paths.concat files("evidence/core-v1/**/*.{json,yaml,yml}", "evidence/reports/**/*.{json,yaml,yml}")
    paths.concat files("evidence/*.evidence.{json,yaml,yml}", "evals/*.definitive-skill-eval.json")
    index_path = absolute("evidence/scenarios/index.json")
    if File.file?(index_path)
      index = JSON.parse(File.read(index_path))
      paths.concat index.fetch("files").map { |item| item.fetch("path") }
    end
    paths.concat definitive_paths

    # PostgreSQL-specific Evidence denominator: all executed Lab artifacts,
    # their generated harness manifests, and dedicated Scenario captures.
    paths.concat files(
      "evidence/artifacts/*", "evidence/harnesses/*.manifest",
      "artifacts/reference-system/**/*", "artifacts/pattern-scenarios/**/*"
    )
    paths.select { |path| File.file?(absolute(path)) }.uniq.sort
  end

  # Full-run ledger denominator. This tracks only files that the full rerun
  # actually publishes or that the tracked generator phase rewrites before the
  # final Graph step.
  def ledger_output_paths
    files(
      "evidence/*.evidence.{json,yaml,yml}",
      "evidence/artifacts/**/*",
      "evidence/harnesses/*.manifest",
      "evidence/scenarios/**/*",
      "artifacts/**/*",
      "evals/**/*.json",
      "provenance.yaml"
    )
      .select { |path| ledger_output_path?(path) }
      .uniq.sort
  end

  def ledger_output_path?(path)
    return false if [LEDGER_PATH, GRAPH_PATH, "evals/cases.json"].include?(path)
    return true if path == "provenance.yaml"
    return true if path.start_with?("artifacts/")
    return true if path.start_with?("evidence/artifacts/", "evidence/harnesses/", "evidence/scenarios/")
    return true if path.start_with?("evidence/") && path.match?(%r{\Aevidence/[^/]+\.evidence\.(json|ya?ml)\z})
    path.start_with?("evals/") && path.end_with?(".json")
  end

  def current_output_bindings(include_graph: true)
    bindings = ledger_output_paths.map do |path|
      {"path"=>path, "digest"=>digest_file(path)}
    end
    if include_graph && File.file?(absolute(GRAPH_PATH))
      bindings << {"path"=>GRAPH_PATH, "digest"=>digest_file(GRAPH_PATH)}
    end
    bindings.sort_by { |binding| binding.fetch("path") }
  end

  def output_id(path)
    "output.#{Digest::SHA256.hexdigest(path)[0, 20]}"
  end

  def output_kind(path)
    return "closure-plan" if path == "evidence/scenarios/closure-plan.json"
    return "scenario-proof" if path.start_with?("evidence/scenarios/") || path.start_with?("artifacts/pattern-scenarios/")
    return "skill-eval" if path.start_with?("evals/") || path.include?("skill-router")
    return "reference-system" if path.include?("reference-system")
    return "compatibility" if path.include?("compatibility") || path.include?("migration") || path.include?("upgrade")
    return "benchmark" if path.include?("performance") || path.include?("statistics")
    return "capture" if path.end_with?(".log") || path.include?("/traces/") || path.include?("/observations/")
    return "derived-evidence" if path == "provenance.yaml" || path.include?("/harnesses/")

    "runtime-evidence"
  end

  def proof_structure_digest
    index = JSON.parse(File.read(absolute("evidence/scenarios/index.json")))
    rows = index.fetch("files").map do |item|
      proof = JSON.parse(File.read(absolute(item.fetch("path"))))
      bindings = proof.fetch("source_bindings").map do |binding|
        {"variant_id"=>binding["variant_id"], "path"=>binding["path"]}
      end
      {
        "id"=>item["id"], "pattern_id"=>item["pattern_id"], "scenario"=>item["scenario"],
        "path"=>item["path"], "proof_id"=>proof["id"], "target_id"=>proof["target_id"],
        "target_set"=>proof["target_set"], "behavior_scope"=>proof["behavior_scope"],
        "source_bindings"=>bindings
      }
    end
    digest_canonical({"id"=>index["id"], "atlas_id"=>index["atlas_id"], "denominator"=>index["denominator"], "files"=>rows})
  end

  def closure_plan_structure_digest
    plan = JSON.parse(File.read(absolute("evidence/scenarios/closure-plan.json")))
    tranches = %w[completed_tranches tranches].flat_map do |field|
      Array(plan[field]).map do |item|
        {
          "id"=>item["id"], "risk_rank"=>item["risk_rank"], "scenario"=>item["scenario"],
          "row_ids"=>item["row_ids"], "pattern_rows"=>item["pattern_rows"],
          "variant_runs"=>item["variant_runs"], "commit_policy"=>item["commit_policy"]
        }
      end
    end
    row_ids = Array(plan["completed_tranches"]).flat_map { |item| Array(item["row_ids"]) } +
      Array(plan["rows"]).map { |item| item["id"] }
    digest_canonical({
      "id"=>plan["id"], "scope"=>plan["scope"], "policy"=>plan["policy"],
      "baseline"=>plan["baseline"], "tranches"=>tranches, "ordered_row_ids"=>row_ids
    })
  end

  def build
    ledger = JSON.parse(File.read(absolute(LEDGER_PATH)))
    verify_ledger_output_bindings!(ledger, require_graph: false)
    prior = File.file?(absolute(GRAPH_PATH)) ? JSON.parse(File.read(absolute(GRAPH_PATH))) : nil
    prior_inputs = Array(prior&.fetch("inputs", [])).to_h { |item| [item.fetch("id"), item] }
    ledger_bindings = ledger.fetch("input_bindings").to_h { |item| [item.fetch("input_id"), item.fetch("digest")] }
    rebound_inputs = Array(ledger.dig("refresh_context", "allowed_input_drift"))
    inputs = current_input_bindings.map do |binding|
      id, current = binding.fetch("id"), binding.fetch("digest")
      raise "Rerun ledgerが現在の入力へ結ばれていません: #{id}" unless ledger_bindings[id] == current
      previous = prior_inputs[id]
      changed_now = previous && previous.fetch("current_digest") != current
      observed_at = if rebound_inputs.include?(id)
                      ledger.fetch("observed_at")
                    elsif changed_now
                      ledger.fetch("observed_at")
                    else
                      previous&.fetch("observed_at") || ledger.fetch("observed_at")
                    end
      {
        "id"=>id, "kind"=>binding.fetch("kind"), "members"=>binding.fetch("members"),
        "baseline_digest"=>previous ? previous.fetch("baseline_digest") : current,
        "current_digest"=>current,
        "observed_at"=>observed_at
      }
    end
    paths = required_output_paths
    input_ids = inputs.map { |input| input.fetch("id") }
    outputs = paths.map do |path|
      {
        "id"=>output_id(path), "kind"=>output_kind(path), "path"=>path,
        "digest"=>digest_file(path), "depends_on"=>input_ids,
        "status"=>"current", "run_id"=>ledger.fetch("id")
      }
    end
    run = {
      "id"=>ledger.fetch("id"), "execution_kind"=>"runtime",
      "command"=>ledger.fetch("command"), "started_at"=>ledger.fetch("started_at"),
      "completed_at"=>ledger.fetch("completed_at"), "result"=>"passed", "attempts"=>1,
      "runtime_identity"=>ledger.fetch("runtime_identity"),
      "input_bindings"=>inputs.map { |input| {"input_id"=>input.fetch("id"), "digest"=>input.fetch("current_digest")} },
      "output_ids"=>outputs.map { |output| output.fetch("id") }
    }
    {
      "schema_version"=>1, "atlas_id"=>"postgresql-reference-atlas",
      "generated_at"=>ledger.fetch("completed_at"), "status"=>"current", "policy"=>POLICY,
      "inputs"=>inputs, "outputs"=>outputs, "runs"=>[run], "required_outputs"=>paths,
      "structures"=>[
        {"id"=>"postgresql-scenario-proof-topology-v1", "kind"=>"scenario-proof-index", "path"=>"evidence/scenarios/index.json", "baseline_digest"=>proof_structure_digest},
        {"id"=>"postgresql-scenario-closure-topology-v1", "kind"=>"scenario-closure-plan", "path"=>"evidence/scenarios/closure-plan.json", "baseline_digest"=>closure_plan_structure_digest}
      ]
    }
  end

  def verify_ledger_input_bindings!(ledger_bindings, bindings = current_input_bindings)
    bindings.each do |binding|
      id = binding.fetch("id")
      current = binding.fetch("digest")
      raise "Rerun ledgerが現在の入力へ結ばれていません: #{id}" unless ledger_bindings[id] == current
    end
  end

  def verify!(graph)
    ledger = JSON.parse(File.read(absolute(LEDGER_PATH)))
    verify_ledger_output_bindings!(ledger, require_graph: true)
    raise "Dependency Graph policyが変化しています" unless graph.fetch("policy") == POLICY
    raise "Dependency Graphはstaleです" unless graph.fetch("status") == "current"
    inputs = graph.fetch("inputs").to_h { |item| [item.fetch("id"), item] }
    inputs.each_value do |input|
      actual = aggregate_member_digest(input.fetch("members"))
      raise "入力digestが実体と一致しません: #{input.fetch('id')}" unless actual == input.fetch("current_digest")
    end
    outputs = graph.fetch("outputs").to_h { |item| [item.fetch("id"), item] }
    output_paths = outputs.values.map { |item| item.fetch("path") }.sort
    expected_paths = required_output_paths
    missing = expected_paths - graph.fetch("required_outputs")
    raise "必要outputが機械列挙から退避されています: #{missing.first}" unless missing.empty?
    raise "required outputに対応するnodeがありません" unless (graph.fetch("required_outputs") - output_paths).empty?
    outputs.each_value do |output|
      raise "outputがstaleです: #{output.fetch('id')}" unless output.fetch("status") == "current"
      raise "output digestが実体と一致しません: #{output.fetch('path')}" unless digest_file(output.fetch("path")) == output.fetch("digest")
      raise "outputに入力依存がありません: #{output.fetch('id')}" if (output.fetch("depends_on") & inputs.keys).empty?
    end
    runs = graph.fetch("runs").to_h { |run| [run.fetch("id"), run] }
    outputs.each_value do |output|
      run = runs.fetch(output.fetch("run_id"))
      raise "再実行対象からoutputが漏れています: #{output.fetch('id')}" unless run.fetch("output_ids").include?(output.fetch("id"))
      bound = run.fetch("input_bindings").to_h { |item| [item.fetch("input_id"), item.fetch("digest")] }
      output.fetch("depends_on").each do |input_id|
        raise "再実行が現在の入力へ結ばれていません: #{input_id}" unless bound[input_id] == inputs.fetch(input_id).fetch("current_digest")
        next if inputs.fetch(input_id).fetch("baseline_digest") == inputs.fetch(input_id).fetch("current_digest")
        observed = Time.iso8601(inputs.fetch(input_id).fetch("observed_at"))
        started = Time.iso8601(run.fetch("started_at"))
        raise "digest書換えだけではClosureできません: #{input_id}" if started < observed
      end
    end
    actual_structures = {
      "scenario-proof-index"=>proof_structure_digest,
      "scenario-closure-plan"=>closure_plan_structure_digest
    }
    graph.fetch("structures").each do |structure|
      raise "Proof/Closure Plan構造が縮小または変更されています: #{structure.fetch('kind')}" unless actual_structures.fetch(structure.fetch("kind")) == structure.fetch("baseline_digest")
    end
    true
  end

  def verify_ledger_output_bindings!(ledger, require_graph: true)
    bindings = Array(ledger["output_bindings"]).to_h { |item| [item.fetch("path"), item.fetch("digest")] }
    expected = ledger_output_paths
    missing = expected - bindings.keys
    raise "Generated output bindingが不足しています: #{missing.first}" unless missing.empty?
    unexpected = bindings.keys - expected - [GRAPH_PATH]
    raise "Generated output denominator外のbindingがあります: #{unexpected.first}" unless unexpected.empty?
    expected.each do |path|
      unless File.file?(absolute(path)) && bindings.fetch(path) == digest_file(path)
        raise "Generated outputがfull rerun ledgerと一致しません: #{path}"
      end
    end
    if require_graph
      raise "Final Graph output bindingが不足しています" unless bindings.key?(GRAPH_PATH)
      unless File.file?(absolute(GRAPH_PATH)) && bindings.fetch(GRAPH_PATH) == digest_file(GRAPH_PATH)
        raise "Final Graph outputがfull rerun ledgerと一致しません"
      end
    end
    true
  end
end
