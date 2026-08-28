#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/scenario_proofs"

root = ScenarioProofs::ROOT
index_path = File.join(root, "evidence/scenarios/index.json")
abort "Scenario Proof index is missing" unless File.file?(index_path)
index = JSON.parse(File.read(index_path))
errors = []
errors << "index identity" unless index.fetch("schema_version") == 1 && index.fetch("id") == "postgresql-scenario-proof-matrix-v1" && index.fetch("atlas_id") == "postgresql-reference-atlas"
errors << "index status" unless index.fetch("status") == "incomplete-authority-atomic-and-runtime-closure"
errors << "denominator" unless index.fetch("denominator") == "29-current-domain-behaviors-x-10-scenarios"
errors << "FE method lock" unless index.fetch("completion_limits").any? { |item| item.include?("f2e4c4b19156f8e993f48cdcbce23679ad881924") && item.include?("絶対件数は転用しない") }

expected_proofs, behaviors = ScenarioProofs.build
expected_pairs = expected_proofs.map { |proof| [proof.fetch("behavior_id"), proof.fetch("scenario")] }.sort
actual_paths = Dir.glob(File.join(root, "evidence/scenarios/behaviors/**/*.proof.json")).sort
indexed_paths = index.fetch("files").map { |item| File.join(root, item.fetch("path")) }.sort
errors << "proof file count" unless behaviors.length == 29 && actual_paths.length == 290 && indexed_paths.length == 290
errors << "proof file set" unless actual_paths == indexed_paths
errors << "proof IDs" unless index.fetch("files").map { |item| item.fetch("id") }.uniq.length == 290

actual_proofs = []
index.fetch("files").each do |entry|
  path = File.join(root, entry.fetch("path"))
  unless File.file?(path)
    errors << "missing proof: #{entry.fetch("path")}"; next
  end
  errors << "proof digest: #{entry.fetch("path")}" unless ScenarioProofs.sha256(path) == entry.fetch("digest")
  proof = JSON.parse(File.read(path))
  actual_proofs << proof
  errors << "proof index identity: #{proof.fetch("id")}" unless [proof.fetch("id"), proof.fetch("pattern_id"), proof.fetch("scenario"), proof.fetch("status")] == [entry.fetch("id"), entry.fetch("pattern_id"), entry.fetch("scenario"), entry.fetch("status")]
  errors << "proof scope: #{proof.fetch("id")}" unless proof.fetch("behavior_scope") == "current-domain-pattern-not-authority-atomic" && proof.fetch("pattern_id") == proof.fetch("behavior_id")
  errors << "dedicated row/artifact: #{proof.fetch("id")}" unless proof.dig("closure", "dedicated_row") && proof.dig("closure", "dedicated_artifact")
  errors << "integrated trace separation: #{proof.fetch("id")}" unless proof.dig("closure", "integrated_runtime_trace") && proof.dig("integrated_reference", "pattern_mapped") == false
  errors << "authority overclaim: #{proof.fetch("id")}" unless proof.dig("closure", "authority_atomic_behavior") == false && proof.dig("closure", "completion_eligible") == false
  errors << "authority gap: #{proof.fetch("id")}" unless proof.fetch("gaps").any? { |gap| gap.include?("Authority") }

  identity = proof.dig("pattern_evidence", "capture_environment_identity")
  errors << "identity contract: #{proof.fetch("id")}" unless %w[server client version runtime].all? { |key| %w[observed gap].include?(identity.dig(key, "status")) }
  closure_contract = identity.fetch("closure_contract")
  errors << "strict closure state: #{proof.fetch("id")}" unless proof.fetch("status") == "pattern-specific-gap" && proof.dig("closure", "pattern_specific_evidence") == false && proof.dig("closure", "real_runtime_identity") == false && closure_contract.fetch("gap_closed") == false
  errors << "all-Variant boundary: #{proof.fetch("id")}" unless closure_contract.fetch("variant_denominator_status") == "gap" && closure_contract.fetch("all_variants_executed") == false
  errors << "retry-zero boundary: #{proof.fetch("id")}" unless closure_contract.dig("retry_count", "status") == "gap" && closure_contract.dig("retry_count", "value").nil? && closure_contract.dig("retry_count", "required") == 0
  errors << "reuse boundary: #{proof.fetch("id")}" unless closure_contract.fetch("integrated_reference_credit") == false && closure_contract.fetch("foreign_artifact_metadata_credit") == false
  artifact_records = proof.dig("pattern_evidence", "capture_records")
  artifacts = artifact_records.to_h { |item| [item.fetch("category"), item] }
  errors << "artifact contract: #{proof.fetch("id")}" unless %w[sql plan wal log metric].all? { |key| %w[observed gap].include?(artifacts.dig(key, "status")) }
  identity.values.select { |item| item.is_a?(Hash) && item["status"] == "observed" }.each do |binding|
    target = File.join(root, binding.fetch("path"))
    errors << "identity path: #{proof.fetch("id")}" unless File.file?(target) && ScenarioProofs.sha256(target) == binding.fetch("digest")
  end
  artifacts.values.select { |item| item.fetch("status") == "observed" }.each do |binding|
    target = File.join(root, binding.fetch("path"))
    errors << "artifact path: #{proof.fetch("id")}" unless File.file?(target) && ScenarioProofs.sha256(target) == binding.fetch("digest")
  end
  proof.fetch("source_bindings").each do |binding|
    target = File.join(root, binding.fetch("path"))
    errors << "source binding: #{proof.fetch("id")}" unless File.file?(target) && ScenarioProofs.sha256(target) == binding.fetch("digest")
  end
end
errors << "Cartesian product" unless actual_proofs.map { |proof| [proof.fetch("behavior_id"), proof.fetch("scenario")] }.sort == expected_pairs

index.fetch("source_digests").each do |path, digest|
  absolute = File.join(root, path)
  errors << "source digest: #{path}" unless File.file?(absolute) && ScenarioProofs.sha256(absolute) == digest
end
errors << "tool digest" unless index.fetch("tool_digest") == "sha256:#{Digest::SHA256.hexdigest(JSON.generate(index.fetch("source_digests")))}"

summary = index.fetch("summary")
expected_summary = {
  "patterns"=>behaviors.length, "scenarios"=>ScenarioProofs::SCENARIOS.length, "rows"=>actual_proofs.length,
  "dedicated_artifacts"=>actual_proofs.length,
  "pattern_specific_rows"=>actual_proofs.count { |proof| proof.dig("closure", "pattern_specific_evidence") },
  "pattern_specific_runtime_rows"=>actual_proofs.count { |proof| proof.dig("closure", "real_runtime_identity") },
  "pattern_specific_capture_rows"=>actual_proofs.count { |proof| proof.fetch("status") == "bounded-capture-proof" },
  "pattern_specific_gaps"=>actual_proofs.count { |proof| proof.dig("closure", "pattern_specific_evidence") == false },
  "integrated_trace_rows"=>actual_proofs.count { |proof| proof.dig("closure", "integrated_runtime_trace") },
  "authority_atomic_rows"=>actual_proofs.count { |proof| proof.dig("closure", "authority_atomic_behavior") },
  "completion_eligible_rows"=>actual_proofs.count { |proof| proof.dig("closure", "completion_eligible") }
}
errors << "summary" unless summary == expected_summary
ScenarioProofs::SCENARIOS.each do |scenario|
  rows = actual_proofs.select { |proof| proof.fetch("scenario") == scenario }
  expected = {
    "rows"=>rows.length,
    "pattern_specific"=>rows.count { |proof| proof.dig("closure", "pattern_specific_evidence") },
    "runtime_identity"=>rows.count { |proof| proof.dig("closure", "real_runtime_identity") },
    "integrated_pattern_mapped"=>rows.count { |proof| proof.dig("integrated_reference", "pattern_mapped") },
    "gaps"=>rows.count { |proof| proof.dig("closure", "pattern_specific_evidence") == false }
  }
  errors << "scenario summary: #{scenario}" unless index.dig("by_scenario", scenario) == expected
end
errors << "completion boundary" unless summary.fetch("integrated_trace_rows") == 290 && summary.fetch("authority_atomic_rows") == 0 && summary.fetch("completion_eligible_rows") == 0
errors << "strict Scenario closure boundary" unless summary.fetch("pattern_specific_rows") == 0 && summary.fetch("pattern_specific_runtime_rows") == 0 && summary.fetch("pattern_specific_gaps") == 290
errors << "completion limits" unless index.fetch("completion_limits").length >= 4

abort errors.uniq.join("\n") unless errors.empty?
supporting = actual_proofs.count { |proof| proof.dig("pattern_evidence", "capture_environment_identity", "closure_contract", "bounded_supporting_evidence") }
puts "Verified Scenario Proof Matrix: 290 dedicated artifacts, #{supporting} bounded supporting evidence rows, #{summary.fetch("pattern_specific_rows")} closed scenario rows, #{summary.fetch("pattern_specific_gaps")} scenario gaps."
