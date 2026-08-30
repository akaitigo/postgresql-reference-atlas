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
definitive_skill_routing = JSON.parse(File.read(File.join(root, "evals/postgresql-atlas.definitive-routing-eval.json")))
forward_agent_eval = JSON.parse(File.read(File.join(root, "evals/postgresql-atlas.forward-agent-eval.json")))
scenario_proofs = JSON.parse(File.read(File.join(root, "evidence/scenarios/index.json")))
scenario_closure_plan = JSON.parse(File.read(File.join(root, "evidence/scenarios/closure-plan.json")))
scenario_runtime_report = JSON.parse(File.read(File.join(root, "artifacts/pattern-scenarios/results.json")))

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
skill_contract = mapping.fetch("definitive_skill_eval")
skill_reference = skill_contract.fetch("reference")
errors << "FE definitive skill reference commit" unless skill_reference.fetch("commit") == "8a9e34a89a55cc53702032783c06ede7246a286f"
expected_skill_reference_files = {
  "scripts/lib/definitive-skill-eval.ts"=>["sha256:8209f3deb47eff03a2f88822a7a2af52dd9a3a3d44b74e88e42e84e2c3d1b5b6", 14_502],
  ".agents/skills/fe-behavior-advisor/scripts/advisor-router.mjs"=>["sha256:993326210fecfafa4843d9c11929cddc5bd93c2c9fac6c85a79b9dcf43120c07", 11_194],
  ".agents/skills/fe-behavior-advisor/references/mastery-contract.json"=>["sha256:f2d6ec5bc979cacaee6a8086654449b739d1b88a36134ea8c72b109baf5f376e", 12_132],
  "evals/fe-behavior-advisor.definitive-skill-eval.json"=>["sha256:566c9f3cea248f49c24f769c88695b10c15bbdb956c08bcfa68dbe7e96c18d0a", 747_614]
}
locked_skill_reference_files = skill_reference.fetch("files").to_h { |item| [item.fetch("path"), [item.fetch("digest"), item.fetch("size_bytes")]] }
errors << "FE definitive skill reference file lock" unless locked_skill_reference_files == expected_skill_reference_files
if File.directory?(File.join(frontend_repo, ".git"))
  skill_reference_verified = expected_skill_reference_files.all? do |relative, (expected_digest, expected_size)|
    body, _stderr, status = Open3.capture3("git", "-C", frontend_repo, "show", "8a9e34a89a55cc53702032783c06ede7246a286f:#{relative}")
    status.success? && body.bytesize == expected_size && "sha256:#{Digest::SHA256.hexdigest(body)}" == expected_digest
  end
  errors << "FE definitive skill reference source verification" unless skill_reference_verified
end
skill_policy = skill_contract.fetch("policy")
errors << "Skill matrix completion boundary" unless skill_policy.fetch("matrix_pass_counts_as_completion") == false
errors << "Skill authorization boundary" unless skill_policy.fetch("require_mutation_authorization") == true
errors << "Skill human/stale boundary" unless skill_policy.fetch("human_authority_and_stale_relock_fail_closed") == true
errors << "Skill ambiguous/unknown boundary" unless skill_policy.fetch("ambiguous_and_unknown_query_fail_closed") == true
errors << "Skill all Target state policy" unless skill_policy.fetch("require_all_target_states") == true
errors << "Skill independent Agent record policy" unless skill_policy.fetch("require_independent_agent_forward_eval_record") == true
scenario_contract = mapping.fetch("reference_system_scenario_proof")
scenario_reference = scenario_contract.fetch("reference")
scenario_reference_commit = "f2e4c4b19156f8e993f48cdcbce23679ad881924"
errors << "FE Reference System reference commit" unless scenario_reference.fetch("commit") == scenario_reference_commit
expected_scenario_reference_files = {
  "scripts/lib/scenario-proof.ts"=>["sha256:8b89ff8d0f042b181abe22a2fb1280546f7534f0525a931c6437a177fdb2432f", 20_748],
  "scripts/generate-scenario-proofs.ts"=>["sha256:4b095074665cec1c66c80948baaafaaafeef31919b3afa6c3064681d7a951241", 392],
  "scripts/verify-scenario-proofs.ts"=>["sha256:d6192f7da3b160300690f3a4168846711b366b77f8fc6c28918733db221005cd", 16_599],
  "scripts/verify-pattern-scenario-evidence.ts"=>["sha256:3643d1dd6ab6830d1a729fc0684a6691e8fc7af4b2d85bae3e5ec01d89113469", 6_349],
  "docs/REFERENCE_SYSTEM.md"=>["sha256:5562aa75e57c518c402c31d97885083bed3d1e3abc0af2ecade5c5cb3f188d49", 3_705]
}
locked_scenario_reference_files = scenario_reference.fetch("files").to_h { |item| [item.fetch("path"), [item.fetch("digest"), item.fetch("size_bytes")]] }
errors << "FE Reference System file lock" unless locked_scenario_reference_files == expected_scenario_reference_files
if File.directory?(File.join(frontend_repo, ".git"))
  scenario_reference_verified = expected_scenario_reference_files.all? do |relative, (expected_digest, expected_size)|
    body, _stderr, status = Open3.capture3("git", "-C", frontend_repo, "show", "#{scenario_reference_commit}:#{relative}")
    status.success? && body.bytesize == expected_size && "sha256:#{Digest::SHA256.hexdigest(body)}" == expected_digest
  end
  errors << "FE Reference System source verification" unless scenario_reference_verified
end
scenario_policy = scenario_contract.fetch("policy")
errors << "Scenario count policy" unless scenario_policy.fetch("scenarios") == 10
errors << "Integrated/behavior proof separation" unless scenario_policy.fetch("separate_integrated_and_behavior_specific_proof") == true && scenario_policy.fetch("integrated_success_counts_as_behavior_proof") == false
errors << "Scenario identity-or-gap policy" unless scenario_policy.fetch("require_server_client_version_runtime_identity_or_gap") == true
errors << "Scenario artifact-or-gap policy" unless scenario_policy.fetch("require_sql_plan_wal_log_metric_artifact_or_gap") == true
errors << "Scenario all-Variant runtime policy" unless scenario_policy.fetch("require_all_variants_dedicated_runtime") == true
errors << "Scenario retry policy" unless scenario_policy.fetch("required_retry_count") == 0
errors << "Scenario Oracle and digest policy" unless scenario_policy.fetch("require_dedicated_oracle") == true && scenario_policy.fetch("require_source_and_harness_digest") == true
errors << "Scenario reuse policy" unless scenario_policy.fetch("integrated_reference_reuse_for_closure") == false && scenario_policy.fetch("foreign_artifact_metadata_reuse_for_closure") == false
errors << "Scenario Authority completion policy" unless scenario_policy.fetch("authority_atomic_binding_required_for_completion") == true
errors << "Scenario absolute count transplant policy" unless scenario_policy.fetch("absolute_counts_transplanted") == false
scenario_summary = scenario_proofs.fetch("summary")
errors << "PostgreSQL Scenario Proof identity" unless scenario_proofs.fetch("id") == "postgresql-scenario-proof-matrix-v1" && scenario_proofs.fetch("status") == "incomplete-authority-atomic-and-runtime-closure"
errors << "PostgreSQL Scenario Proof denominator" unless scenario_summary.fetch("patterns") == 29 && scenario_summary.fetch("scenarios") == 10 && scenario_summary.fetch("rows") == 290
errors << "PostgreSQL Scenario Proof non-reuse" unless scenario_summary.fetch("integrated_trace_rows") == 290 && scenario_proofs.fetch("files").all? { |item| item.fetch("status") != "completion-eligible-runtime-proof" }
errors << "PostgreSQL strict Scenario closure" unless scenario_summary.fetch("pattern_specific_rows") == 12 && scenario_summary.fetch("pattern_specific_runtime_rows") == 12 && scenario_summary.fetch("pattern_specific_gaps") == 278
errors << "PostgreSQL Scenario Proof completion boundary" unless scenario_summary.fetch("authority_atomic_rows") == 0 && scenario_summary.fetch("completion_eligible_rows") == 0
closure_plan_contract = mapping.fetch("scenario_closure_plan")
closure_plan_reference = closure_plan_contract.fetch("reference")
closure_plan_reference_commit = "8329cb3c09e034b36b8cbe35021f7dd7b52d4140"
errors << "FE Scenario Closure Plan reference commit" unless closure_plan_reference.fetch("commit") == closure_plan_reference_commit
expected_closure_plan_reference_files = {
  "scripts/lib/scenario-closure-plan.ts"=>["sha256:3bfc98ffdda5e114ab265eb4914abd63c7c8c58bc6409fcdb68ae2fb17b0a58d", 5_784],
  "scripts/generate-scenario-closure-plan.ts"=>["sha256:df449779a8320615ef6a7c6b206961c400505bf08a6b8a6b4c356ec72fd48b16", 519],
  "scripts/verify-scenario-closure-plan.ts"=>["sha256:3bbeeba3cb987ec456b80e1eb6c6f4fe36a24f241d1607d5e49194940b765116", 2_903],
  "evidence/scenarios/closure-plan.json"=>["sha256:ccf4f82e8713f3c4d8a14833935fd6f87d904a4e56e61a555e463d450a04f5fe", 694_882]
}
locked_closure_plan_reference_files = closure_plan_reference.fetch("files").to_h { |item| [item.fetch("path"), [item.fetch("digest"), item.fetch("size_bytes")]] }
errors << "FE Scenario Closure Plan file lock" unless locked_closure_plan_reference_files == expected_closure_plan_reference_files
if File.directory?(File.join(frontend_repo, ".git"))
  closure_plan_reference_verified = expected_closure_plan_reference_files.all? do |relative, (expected_digest, expected_size)|
    body, _stderr, status = Open3.capture3("git", "-C", frontend_repo, "show", "#{closure_plan_reference_commit}:#{relative}")
    status.success? && body.bytesize == expected_size && "sha256:#{Digest::SHA256.hexdigest(body)}" == expected_digest
  end
  errors << "FE Scenario Closure Plan source verification" unless closure_plan_reference_verified
end
closure_plan_policy = closure_plan_contract.fetch("policy")
errors << "Scenario Closure risk order" unless closure_plan_policy.fetch("risk_order") == %w[security refusal failure recovery migration operations boundary performance compatibility normal]
errors << "Scenario Closure tranche size" unless closure_plan_policy.fetch("maximum_pattern_rows_per_tranche") == 4
errors << "Scenario Closure Subject denominator" unless closure_plan_policy.fetch("derive_counts_from_postgresql_denominator") == true && closure_plan_policy.fetch("transplant_frontend_absolute_counts") == false
closure_plan_summary = scenario_closure_plan.fetch("summary")
errors << "PostgreSQL Scenario Closure Plan denominator" unless closure_plan_summary.fetch("remaining_rows") == 278 && closure_plan_summary.fetch("completed_dedicated_rows") == 12 && closure_plan_summary.fetch("planned_tranches") == 77
errors << "PostgreSQL Scenario Closure Plan next tranche" unless scenario_closure_plan.dig("next_tranche", "id") == "security-001" && scenario_closure_plan.fetch("tranches").all? { |tranche| tranche.fetch("pattern_rows") <= 4 }

atomic_contract = mapping.fetch("atomic_scenario_evidence_publishing")
atomic_reference = atomic_contract.fetch("reference")
errors << "FE atomic Evidence reference commit" unless atomic_reference.fetch("commit") == "7175de4"
expected_atomic_reference_files = {
  "scripts/reporters/pattern-scenario-evidence-reporter.ts"=>["sha256:fa93509b82141deb456e1218095de52a147c88d2b7e6f8e0e5df2725e92ad330", 10_029],
  "scripts/verify-pattern-scenario-evidence.ts"=>["sha256:fc05990ab4a02a075f72badf60190dc3e584fe62acf52a31c179b99c90e3e0fd", 16_291],
  "docs/REFERENCE_SYSTEM.md"=>["sha256:33d8b7d1c4cd0b01e094f3c1c805cfb0d6e2e7f2862305cb6daffc2852fe8bb9", 4_793]
}
locked_atomic_reference_files = atomic_reference.fetch("files").to_h { |item| [item.fetch("path"), [item.fetch("digest"), item.fetch("size_bytes")]] }
errors << "FE atomic Evidence file lock" unless locked_atomic_reference_files == expected_atomic_reference_files
if File.directory?(File.join(frontend_repo, ".git"))
  atomic_reference_verified = expected_atomic_reference_files.all? do |relative, (expected_digest, expected_size)|
    body, _stderr, status = Open3.capture3("git", "-C", frontend_repo, "show", "7175de4:#{relative}")
    status.success? && body.bytesize == expected_size && "sha256:#{Digest::SHA256.hexdigest(body)}" == expected_digest
  end
  errors << "FE atomic Evidence source verification" unless atomic_reference_verified
end
atomic_policy = atomic_contract.fetch("policy")
errors << "Atomic Evidence policy" unless atomic_policy.values.all? { |value| value == true }
errors << "Atomic Evidence implementation" unless File.file?(File.join(root, atomic_contract.fetch("implementation"))) && File.file?(File.join(root, atomic_contract.fetch("negative_test")))
errors << "Atomic Evidence runtime report" unless scenario_runtime_report.fetch("status") == "passed" && scenario_runtime_report.fetch("retention_contract") == {"publish_on"=>"full-run-passed", "failed_run"=>"retain-prior-success", "swap"=>"staged-directory-rename-with-rollback"} && scenario_runtime_report.fetch("tests").length == 12
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
skill_summary = definitive_skill_routing.fetch("summary")
errors << "Definitive Skill 8x14 matrix" unless skill_summary.fetch("outcomes") == 8 && skill_summary.fetch("surfaces") == 14 && skill_summary.fetch("matrix_cells") == 112 && skill_summary.fetch("contract_passed") == 112 && skill_summary.fetch("contract_failed") == 0
errors << "Definitive Skill routing gap disclosure" unless skill_summary.fetch("bounded_evidence_routes") + skill_summary.fetch("routing_gaps") == 112 && skill_summary.fetch("routing_gaps") > 0
errors << "Definitive Skill Target states" unless skill_summary.fetch("targets") == 56 && skill_summary.fetch("covered_targets") == 29 && skill_summary.fetch("partial_targets") == 16 && skill_summary.fetch("planned_targets") == 11
errors << "Definitive Skill Matrix cannot complete Subject" unless skill_summary.fetch("matrix_pass_counts_as_completion") == false
errors << "Definitive Skill boundary cases" unless skill_summary.fetch("boundary_cases") == 5 && skill_summary.fetch("boundary_passed") == 5 && skill_summary.fetch("boundary_failed") == 0
errors << "Independent Agent Forward Eval binding" unless definitive_skill_routing.fetch("independent_agent_forward_eval") == forward_agent_eval
errors << "Independent Agent Forward Eval completion boundary" unless forward_agent_eval.fetch("completion_credit") == false && %w[pass fail inconclusive].include?(forward_agent_eval.fetch("result"))
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
  "definitive_skill_eval"=>skill_summary,
  "reference_system_scenario_proof"=>scenario_proofs.slice("status", "denominator", "denominator_scope", "summary", "by_scenario", "completion_limits"),
  "independent_agent_forward_eval"=>forward_agent_eval.slice("status", "reviewer", "evaluated_commit", "prompt_digest", "result", "completion_credit"),
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
