#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "yaml"

root = File.expand_path("..", __dir__)
mapping = YAML.safe_load(File.read(File.join(root, "postgresql-depth-parity.yaml")), aliases: false)
inventory = YAML.safe_load(File.read(File.join(root, "surface.inventory.yaml")), aliases: false)
matrix = YAML.safe_load(File.read(File.join(root, "verification.matrix.yaml")), aliases: false)
definitive = JSON.parse(File.read(File.join(root, "evidence/definitive-audit-report.json")))
non_regression = JSON.parse(File.read(File.join(root, "evidence/non-regression-audit-report.json")))
locator_extraction = JSON.parse(File.read(File.join(root, "authority/locator-extraction.snapshot.json")))
core_authority_extraction = JSON.parse(File.read(File.join(root, "authority/extraction.snapshot.json")))

required_axes = %w[
  authority-body-digestion surface-atomic-behavior-variant real-runtime-lab
  scenario-normal scenario-boundary scenario-refusal scenario-failure scenario-recovery
  scenario-migration scenario-operations scenario-security scenario-performance scenario-compatibility
  artifact-trace integrated-reference-system skill-eval rights-provenance non-regression-gate
]
errors = []
errors << "FE reference commit" unless mapping.dig("frontend_reference", "commit") == "4a0b2df8e2091a963bd0e0e1bbccef9c84b49a45"
reference_path = File.join(root, "authority/FE_DEPTH_REFERENCE.json")
reference_document = File.file?(reference_path) ? JSON.parse(File.read(reference_path)) : {}
reference_digest = File.file?(reference_path) ? "sha256:#{Digest::SHA256.file(reference_path).hexdigest}" : nil
errors << "vendored FE reference digest" unless reference_digest == "sha256:2452696f9807b7d4a8ffb22b3ba37f079a25a34ac2370d78423445b96064582a"
expected_files = {
  "FE_DEPTH_REFERENCE.json"=>["sha256:2452696f9807b7d4a8ffb22b3ba37f079a25a34ac2370d78423445b96064582a", 31_657],
  "docs/DEFINITIVE_GATE_V2_REFERENCE.md"=>["sha256:280a398ed1251438ad244e999c9c9cef9b0b6b78217db82e2b55ef882306d241", 4_435],
  "fixtures/definitive-gate-v2/authority-surface-inventory.fixture.json"=>["sha256:01c29cdd29f61968b06791edf3d0d0674462d279422bd312d523ab7964e2a1e4", 1_783],
  "fixtures/definitive-gate-v2/variant-comparison.fixture.json"=>["sha256:2964d596201033761c083d06dc705d21a428de043a91a0f1e71e7d5b841f59d3", 2_306],
  "fixtures/definitive-gate-v2/profile-incompatibility.fixture.json"=>["sha256:95c07992da4b78db5c5551d7ed0c4425668dde9188c0acb53c3b76b17a91e364", 2_209],
  "fixtures/definitive-gate-v2/evidence-granularity.fixture.json"=>["sha256:94506646f1e30429cb84a87927e1af7e1e890d401efd0335ebf911aed6f85126", 3_590],
  "baselines/definitive-gate-v2.json"=>["sha256:b6685fac1e11429ed7c203e35aac55c7a82c276dc32aadb97f225af801c3bb67", 656_649]
}
locked_files = mapping.dig("frontend_reference", "files").to_h { |item| [item.fetch("path"), [item.fetch("digest"), item.fetch("size_bytes")]] }
errors << "FE reference file lock" unless locked_files == expected_files
frontend_repo = File.expand_path("../frontend-behavior-atlas", root)
frontend_source_verified = false
if File.directory?(File.join(frontend_repo, ".git"))
  frontend_source_verified = expected_files.all? do |relative, (expected_digest, expected_size)|
    body, _stderr, status = Open3.capture3(
      "git", "-C", frontend_repo, "show",
      "4a0b2df8e2091a963bd0e0e1bbccef9c84b49a45:#{relative}"
    )
    status.success? && body.bytesize == expected_size && "sha256:#{Digest::SHA256.hexdigest(body)}" == expected_digest
  end
  errors << "FE reference source verification" unless frontend_source_verified
end
axes = mapping.fetch("axes")
errors << "18 axes" unless axes.map { |axis| axis.fetch("id") } == required_axes
errors << "FE canonical axes" unless Array(reference_document["axes"]).map { |axis| axis.fetch("id") } == required_axes
errors << "FE canonical incomplete summary" unless reference_document["status"] == "incomplete" && reference_document["summary"] == {"satisfied"=>1, "partial"=>17, "missing"=>0}
errors << "absolute counts must not be a threshold" unless mapping["absolute_count_threshold"].nil?
errors << "completion status" unless mapping.fetch("completion_status") == "incomplete"
locator_reference = mapping.fetch("authority_locator_reference")
errors << "FE locator reference commit" unless locator_reference.fetch("commit") == "cabf687bab769b17928d950acc416f3f77eb4ca3"
errors << "locator body storage policy" unless locator_reference.dig("policy", "body_storage") == "digest-and-locator-offset-only"
errors << "generated candidates must not imply exhaustive authority text" unless locator_reference.dig("policy", "generated_candidates_are_authority_text_exhaustive") == false
errors << "locator reference explicit count policy" unless locator_reference.dig("policy", "require_explicit_stale_deferred_human_review_counts") == true
expected_locator_files = {
  "scripts/lib/authority-extraction.ts"=>["sha256:d0efb14e943384b363f6596cff32371368ad69d4aa319de4c7f5ecf189cb8c7c", 17_508],
  "scripts/verify-authority-extraction.ts"=>["sha256:420acbe08bff848786c4a28febb4443c671afdd53ff1643413317a9ce175d9aa", 121]
}
locked_locator_files = locator_reference.fetch("files").to_h { |item| [item.fetch("path"), [item.fetch("digest"), item.fetch("size_bytes")]] }
errors << "FE locator reference file lock" unless locked_locator_files == expected_locator_files
if File.directory?(File.join(frontend_repo, ".git"))
  locator_source_verified = expected_locator_files.all? do |relative, (expected_digest, expected_size)|
    body, _stderr, status = Open3.capture3("git", "-C", frontend_repo, "show", "cabf687bab769b17928d950acc416f3f77eb4ca3:#{relative}")
    status.success? && body.bytesize == expected_size && "sha256:#{Digest::SHA256.hexdigest(body)}" == expected_digest
  end
  errors << "FE locator reference source verification" unless locator_source_verified
end
axes.each do |axis|
  errors << "criterion #{axis.fetch("id")}" if axis.fetch("portable_criterion").length < 30
  errors << "denominator #{axis.fetch("id")}" if axis.fetch("postgresql_denominator").length < 15
  if axis.fetch("status") == "satisfied"
    errors << "satisfied gap #{axis.fetch("id")}" unless axis.fetch("gaps").empty?
  else
    errors << "partial gap #{axis.fetch("id")}" unless axis.fetch("status") == "partial" && axis.fetch("gaps").any?
  end
  axis.fetch("evidence").each { |relative| errors << "evidence path #{relative}" unless File.exist?(File.join(root, relative)) }
end
errors << "only non-regression satisfied" unless axes.select { |axis| axis.fetch("status") == "satisfied" }.map { |axis| axis.fetch("id") } == ["non-regression-gate"]
errors << "non-regression report" unless non_regression.fetch("verdict") == "pass"

items = inventory.fetch("items")
locator_summary = locator_extraction.fetch("summary")
errors << "locator candidate denominator" unless locator_summary.fetch("candidate_surfaces") == items.length
errors << "locator body storage" unless locator_extraction.fetch("body_storage") == "digest-and-locator-offset-only"
errors << "generated candidate exhaustive boundary" unless locator_summary.fetch("generated_surface_candidates_exhaustive") == true
errors << "authority text exhaustive boundary" unless locator_summary.fetch("authority_text_surfaces_exhaustive") == false
errors << "authority denominator closure boundary" unless locator_summary.fetch("postgresql_authority_denominator_closed") == false
errors << "human review count" unless locator_summary.fetch("human_reviewed_surfaces") == 0
core_locator_summary = core_authority_extraction.fetch("summary")
errors << "Core authority text exhaustive boundary" unless core_locator_summary.fetch("authority_text_surfaces_exhaustive") == false
errors << "Core authority human review count" unless core_locator_summary.fetch("human_reviewed_surfaces") == 0 && core_locator_summary.fetch("core_v2_eligible_surfaces") == 0
errors << "Core authority failed/deferred disclosure" unless core_locator_summary.fetch("fetch_failed") == 10 && core_locator_summary.fetch("locator_evaluations_deferred") == 10
row_keys = matrix.fetch("rows").map { |row| [row.fetch("behavior_id"), row.fetch("scenario")] }.uniq
surface_scenarios = {
  "failure-recovery"=>%w[failure recovery], "operations-observability"=>%w[operations],
  "security-privacy-safety"=>%w[security], "performance-capacity-cost"=>%w[performance],
  "compatibility-integration"=>%w[compatibility], "migration-evolution-deprecation"=>%w[migration]
}
scenario_metrics = %w[normal boundary rejection failure recovery migration operations security performance compatibility].to_h do |scenario|
  required = items.count do |item|
    (%w[normal boundary rejection] + item.fetch("surface_ids").flat_map { |surface| surface_scenarios.fetch(surface, []) }).uniq.include?(scenario)
  end
  closed = row_keys.count { |behavior, candidate| candidate == scenario && items.any? { |item| item.fetch("behavior_id") == behavior } }
  [scenario, {"required"=>required, "closed"=>closed, "gap"=>required-closed}]
end
runtime_behaviors = matrix.fetch("rows").select { |row| row.fetch("evidence_ids").any? }.map { |row| row.fetch("behavior_id") }.uniq.length
report = {
  "schema_version"=>1, "id"=>mapping.fetch("id"), "atlas_id"=>mapping.fetch("atlas_id"),
  "frontend_reference"=>mapping.fetch("frontend_reference"),
  "frontend_source_verified"=>frontend_source_verified,
  "authority_locator_reference"=>locator_reference,
  "authority_locator_extraction"=>locator_summary,
  "core_authority_extraction"=>core_locator_summary,
  "denominator"=>{
    "authority_behaviors"=>items.length,
    "variant_ids"=>items.sum { |item| Array(item["variant_ids"]).length },
    "runtime_proven_behaviors"=>runtime_behaviors,
    "behaviors_without_dedicated_accepted_claim"=>definitive.dig("verification", "behaviors_without_dedicated_accepted_claim"),
    "scenario_rows"=>scenario_metrics
  },
  "axes"=>axes.map { |axis| {"id"=>axis.fetch("id"), "status"=>axis.fetch("status"), "gap_count"=>axis.fetch("gaps").length, "denominator"=>axis.fetch("postgresql_denominator")} },
  "summary"=>{
    "satisfied"=>axes.count { |axis| axis.fetch("status") == "satisfied" },
    "partial"=>axes.count { |axis| axis.fetch("status") == "partial" },
    "missing"=>axes.count { |axis| axis.fetch("status") == "missing" }
  },
  "structural_errors"=>errors,
  "completion_status"=>errors.empty? ? "incomplete" : "invalid"
}
File.write(File.join(root, "evidence/postgresql-depth-parity-report.json"), JSON.pretty_generate(report) + "\n")
abort errors.join("\n") unless errors.empty?
puts "PostgreSQL depth parity: axes=18 satisfied=#{report.dig("summary", "satisfied")} partial=#{report.dig("summary", "partial")} behaviors=#{items.length} verdict=incomplete"
