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
body_inventory = JSON.parse(File.read(File.join(root, "authority/body-inventory.snapshot.json")))
review_queue = JSON.parse(File.read(File.join(root, "authority/review-queue.snapshot.json")))
review_ledger = JSON.parse(File.read(File.join(root, "authority/reviews/decisions.json")))
body_non_regression = JSON.parse(File.read(File.join(root, "evidence/authority-body-non-regression-report.json")))

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
body_denominator = mapping.fetch("authority_body_denominator")
body_reference = body_denominator.fetch("reference")
errors << "FE body denominator reference commit" unless body_reference.fetch("commit") == "841ec2fa399606a10305021a8bcd396713b8cee5"
expected_body_reference_files = {
  "scripts/lib/authority-body-inventory.ts"=>["sha256:04f62a0b63981c62a7ab90f39637c71745642e84a3bdd4404ce715a0163ebe76", 20_216],
  "scripts/lib/authority-body-baseline.ts"=>["sha256:0dc48dc9e62fdc9cd8493e9b5827b4cf5948c4b72df3374d5ebcc73ac344009c", 8_170]
}
locked_body_reference_files = body_reference.fetch("files").to_h { |item| [item.fetch("path"), [item.fetch("digest"), item.fetch("size_bytes")]] }
errors << "FE body denominator reference file lock" unless locked_body_reference_files == expected_body_reference_files
if File.directory?(File.join(frontend_repo, ".git"))
  body_reference_verified = expected_body_reference_files.all? do |relative, (expected_digest, expected_size)|
    body, _stderr, status = Open3.capture3("git", "-C", frontend_repo, "show", "841ec2fa399606a10305021a8bcd396713b8cee5:#{relative}")
    status.success? && body.bytesize == expected_size && "sha256:#{Digest::SHA256.hexdigest(body)}" == expected_digest
  end
  errors << "FE body denominator reference source verification" unless body_reference_verified
end
%w[inventory baseline].each do |key|
  lock = body_denominator.fetch(key)
  path = File.join(root, lock.fetch("path"))
  errors << "Authority body #{key} file lock" unless File.file?(path) && "sha256:#{Digest::SHA256.file(path).hexdigest}" == lock.fetch("digest") && File.size(path) == lock.fetch("size_bytes")
end
promotion_policy = body_denominator.fetch("promotion_policy")
errors << "Authority body pending-human policy" unless promotion_policy.fetch("initial_status") == "pending-human"
errors << "Raw anchors cannot count as semantic surfaces" unless promotion_policy.fetch("count_raw_anchors_as_semantic_surfaces") == false
errors << "Raw anchors cannot count as depth achievement" unless promotion_policy.fetch("count_raw_anchors_as_depth_achievement") == false
errors << "Human decision promotion policy" unless promotion_policy.fetch("require_human_decision_before_surface_or_behavior") == true
review_contract = mapping.fetch("authority_review_queue")
review_reference = review_contract.fetch("reference")
errors << "FE authority review reference commit" unless review_reference.fetch("commit") == "de2f016b8b44ea67afdb08c0552044807505984e"
expected_review_reference_files = {
  "scripts/lib/authority-review-queue.ts"=>["sha256:6a0d44da874e7332d2212416bcbaa9ca93ab7a2cda9d5c28b846fecb847c2187", 25_181],
  "scripts/generate-authority-review-queue.ts"=>["sha256:0ddb9e1ed3221c89e68449914e37a94a9104123d3ae0578b2e0a4aed3f57f291", 315],
  "scripts/verify-authority-review-queue.ts"=>["sha256:3849bd25a409742acdcbb8e028a65cf0d51249ac29c23ba606a14d63b81524f9", 125],
  "scripts/test-authority-review-queue.ts"=>["sha256:cd6ffd8860645b70f85feb262fffc903d3b0a0aa96c6f9a7181f6ed895e965ec", 2_437],
  "docs/AUTHORITY_REVIEW_WORKFLOW.md"=>["sha256:64c8dad6e3dc1366ad5afb27a7e785dd428de3c6f0f55f4311ff4d3278370fbd", 3_272]
}
locked_review_reference_files = review_reference.fetch("files").to_h { |item| [item.fetch("path"), [item.fetch("digest"), item.fetch("size_bytes")]] }
errors << "FE authority review reference file lock" unless locked_review_reference_files == expected_review_reference_files
if File.directory?(File.join(frontend_repo, ".git"))
  review_reference_verified = expected_review_reference_files.all? do |relative, (expected_digest, expected_size)|
    body, _stderr, status = Open3.capture3("git", "-C", frontend_repo, "show", "de2f016b8b44ea67afdb08c0552044807505984e:#{relative}")
    status.success? && body.bytesize == expected_size && "sha256:#{Digest::SHA256.hexdigest(body)}" == expected_digest
  end
  errors << "FE authority review reference source verification" unless review_reference_verified
end
%w[queue decision_ledger].each do |key|
  lock = review_contract.fetch(key)
  path = File.join(root, lock.fetch("path"))
  errors << "Authority review #{key} file lock" unless File.file?(path) && "sha256:#{Digest::SHA256.file(path).hexdigest}" == lock.fetch("digest") && File.size(path) == lock.fetch("size_bytes")
end
review_policy = review_contract.fetch("policy")
errors << "Authority review pending-human policy" unless review_policy.fetch("initial_status") == "pending-human"
errors << "Machine assistance cannot decide semantics" unless review_policy.fetch("machine_priority_cluster_batch_are_semantic_decisions") == false
errors << "Manual primary-source review policy" unless review_policy.fetch("require_manual_primary_source_review") == true
errors << "Review decision binding policy" unless review_policy.fetch("require_reviewer_time_reason_digest_locator_mapping_result_consistency") == true
errors << "Stale hold policy" unless review_policy.fetch("stale_documents_are_held") == true
errors << "Review queue cannot count as Depth" unless review_policy.fetch("count_queue_items_as_depth_achievement") == false
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
body_summary = body_inventory.fetch("summary")
errors << "Authority body unique document denominator" unless body_summary.fetch("source_entries") == 10 && body_summary.fetch("unique_documents") == 398
errors << "Authority body stale/failure disclosure" unless body_summary.fetch("matched_documents") == 390 && body_summary.fetch("stale_documents") == 0 && body_summary.fetch("failed_documents") == 8
errors << "Authority body raw pending boundary" unless body_summary.fetch("raw_anchor_candidates") == 5_512 && body_summary.fetch("pending_human_anchors") == 5_512 && body_summary.fetch("human_reviewed_anchors") == 0
errors << "Authority body semantic promotion boundary" unless body_summary.fetch("promoted_surface_artifacts") == 0 && body_summary.fetch("promoted_atomic_behaviors") == 0
errors << "Authority body denominator closure boundary" unless body_summary.fetch("authority_semantics_exhaustive") == false && body_summary.fetch("postgresql_authority_denominator_closed") == false
errors << "Authority body non-regression" unless body_non_regression.fetch("status") == "pass" && body_non_regression.fetch("baseline_anchors") == 5_512 && body_non_regression.fetch("retained") == 5_512 && body_non_regression.fetch("replaced") == 0
review_summary = review_queue.fetch("summary")
errors << "Authority review queue identity" unless review_queue.fetch("atlas_id") == mapping.fetch("atlas_id") && review_queue.fetch("status") == "incomplete-human-review-required" && review_ledger.fetch("queue_id") == review_queue.fetch("queue_id")
errors << "Authority review complete queue" unless review_summary.fetch("queued_anchors") == 5_512 && review_summary.fetch("pending_human") == 5_512 && review_summary.fetch("human_reviewed") == 0
errors << "Authority review decisions start empty" unless review_ledger.fetch("decisions") == [] && review_summary.fetch("decisions") == 0
errors << "Authority review hold disclosure" unless review_summary.fetch("stale_document_holds") == 0 && review_summary.fetch("unavailable_document_holds") == 8
errors << "Authority review semantic boundary" unless review_queue.fetch("semantic_decisions") == "human-only" && review_summary.fetch("authority_semantics_exhaustive") == false && review_summary.fetch("queue_counts_as_depth_achievement") == false
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
  "authority_body_denominator"=>body_summary,
  "authority_review_queue"=>review_summary,
  "authority_body_non_regression"=>body_non_regression,
  "denominator"=>{
    "generated_mapping_candidates"=>items.length,
    "raw_anchor_candidates"=>body_summary.fetch("raw_anchor_candidates"),
    "pending_human_anchors"=>body_summary.fetch("pending_human_anchors"),
    "human_reviewed_anchors"=>body_summary.fetch("human_reviewed_anchors"),
    "promoted_semantic_surfaces"=>body_summary.fetch("promoted_surface_artifacts"),
    "promoted_atomic_behaviors"=>body_summary.fetch("promoted_atomic_behaviors"),
    "variant_ids"=>items.sum { |item| Array(item["variant_ids"]).length },
    "provisional_mapping_records_with_runtime_proof"=>runtime_behaviors,
    "generated_mapping_records_without_dedicated_accepted_claim"=>definitive.dig("verification", "behaviors_without_dedicated_accepted_claim"),
    "provisional_scenario_lower_bound"=>scenario_metrics,
    "denominator_closed"=>false
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
puts "PostgreSQL depth parity: axes=18 satisfied=#{report.dig("summary", "satisfied")} partial=#{report.dig("summary", "partial")} raw_anchors=#{body_summary.fetch("raw_anchor_candidates")} promoted_behaviors=0 verdict=incomplete"
