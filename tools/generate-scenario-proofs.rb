#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require_relative "lib/scenario_proofs"

root = ScenarioProofs::ROOT
ScenarioProofs.prepare_integrated_reference
proofs, behaviors = ScenarioProofs.build
output_root = File.join(root, "evidence/scenarios/behaviors")
FileUtils.rm_rf(output_root)
FileUtils.mkdir_p(output_root)

files = proofs.map do |proof|
  relative = "evidence/scenarios/behaviors/#{proof.fetch("target_id")}/#{proof.fetch("scenario")}.proof.json"
  absolute = File.join(root, relative)
  FileUtils.mkdir_p(File.dirname(absolute))
  output = ScenarioProofs.canonical_json(proof) + "\n"
  File.write(absolute, output)
  {
    "id"=>proof.fetch("id"), "behavior_id"=>proof.fetch("behavior_id"), "pattern_id"=>proof.fetch("pattern_id"),
    "scenario"=>proof.fetch("scenario"), "path"=>relative,
    "digest"=>ScenarioProofs.sha256(absolute), "status"=>proof.fetch("status")
  }
end

source_files = %w[
  tools/lib/scenario_proofs.rb
  tools/generate-scenario-proofs.rb
  tools/verify-scenario-proofs.rb
  verification.matrix.yaml
  coverage.yaml
  authority/reviews/decisions.json
  evidence/artifacts/reference-system.json
  integrations/reference-system/manifest.json
  artifacts/reference-system/results.json
  artifacts/pattern-scenarios/results.json
]
source_digests = source_files.to_h { |path| [path, ScenarioProofs.relative_digest(path)] }
by_scenario = ScenarioProofs::SCENARIOS.to_h do |scenario|
  rows = proofs.select { |proof| proof.fetch("scenario") == scenario }
  [scenario, {
    "rows"=>rows.length,
    "pattern_specific"=>rows.count { |proof| proof.dig("closure", "pattern_specific_evidence") },
    "runtime_identity"=>rows.count { |proof| proof.dig("closure", "real_runtime_identity") },
    "integrated_pattern_mapped"=>rows.count { |proof| proof.dig("integrated_reference", "pattern_mapped") },
    "gaps"=>rows.count { |proof| proof.dig("closure", "pattern_specific_evidence") == false }
  }]
end
index = {
  "schema_version"=>1,
  "id"=>"postgresql-scenario-proof-matrix-v1",
  "atlas_id"=>"postgresql-reference-atlas",
  "generated_at"=>ScenarioProofs::GENERATED_AT,
  "status"=>"incomplete-authority-atomic-and-runtime-closure",
  "denominator"=>"29-current-domain-behaviors-x-10-scenarios",
  "source_digests"=>source_digests,
  "tool_digest"=>"sha256:#{Digest::SHA256.hexdigest(JSON.generate(source_digests))}",
  "summary"=>{
    "patterns"=>behaviors.length,
    "scenarios"=>ScenarioProofs::SCENARIOS.length,
    "rows"=>proofs.length,
    "dedicated_artifacts"=>files.length,
    "pattern_specific_rows"=>proofs.count { |proof| proof.dig("closure", "pattern_specific_evidence") },
    "pattern_specific_runtime_rows"=>proofs.count { |proof| proof.dig("closure", "real_runtime_identity") },
    "pattern_specific_capture_rows"=>proofs.count { |proof| proof.fetch("status") == "bounded-capture-proof" },
    "pattern_specific_gaps"=>proofs.count { |proof| proof.dig("closure", "pattern_specific_evidence") == false },
    "integrated_trace_rows"=>proofs.count { |proof| proof.dig("closure", "integrated_runtime_trace") },
    "authority_atomic_rows"=>proofs.count { |proof| proof.dig("closure", "authority_atomic_behavior") },
    "completion_eligible_rows"=>proofs.count { |proof| proof.dig("closure", "completion_eligible") }
  },
  "by_scenario"=>by_scenario,
  "files"=>files,
  "completion_limits"=>[
    "frontend-behavior-atlas f2e4c4b19156f8e993f48cdcbce23679ad881924の方式を使用するが絶対件数は転用しない。",
    "29 Behaviorは公開済みVerification Matrixの非後退分母でありAuthority由来Atomic behavior denominatorではない。",
    "統合Reference Systemの10 Scenario成功、identity、ArtifactをBehavior固有Proofとして流用しない。",
    "各Surface × Scenarioの全Variantを専用実server/clientでretry 0実行し、Oracle、Source/Harness digest、SQL/plan/WAL/log/metricを同じ専用実行へ結ぶまでgapを閉じない。",
    "別Evidence Artifactのmetadataを専用実行Proofとして流用しない。",
    "Authority Human reviewとAtomic behavior bindingがないrowのcompletion eligibleは0を維持する。"
  ]
}
FileUtils.mkdir_p(File.join(root, "evidence/scenarios"))
File.write(File.join(root, "evidence/scenarios/index.json"), ScenarioProofs.canonical_json(index) + "\n")
supporting = proofs.count { |proof| proof.dig("pattern_evidence", "capture_environment_identity", "closure_contract", "bounded_supporting_evidence") }
puts "Generated Scenario Proof Matrix: #{proofs.length} rows, #{supporting} bounded supporting evidence rows, #{index.dig("summary", "pattern_specific_rows")} strict closures, completion eligible=0"
