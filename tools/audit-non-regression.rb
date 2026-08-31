#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

root = File.expand_path("..", __dir__)
baseline = JSON.parse(File.read(File.join(root, "baseline/non-regression-v1.json")))
migration = YAML.safe_load(File.read(File.join(root, "migrations/non-regression-v2.yaml")), aliases: false)
load_yaml = ->(relative) { YAML.safe_load(File.read(File.join(root, relative)), aliases: false) }
sha256 = ->(path) { "sha256:#{Digest::SHA256.file(path).hexdigest}" }
failures = []
approved_mappings = migration.fetch("replacements").to_h { |item| [item.fetch("old_id"), item] }

valid_mapping = lambda do |old_id, expected_digest|
  mapping = approved_mappings[old_id]
  unless mapping
    failures << "Baseline fileの削除または変更にMappingがありません: #{old_id}"
    next false
  end
  evidence_path = File.join(root, mapping.fetch("migration_evidence"))
  evidence = File.file?(evidence_path) ? JSON.parse(File.read(evidence_path)) : {}
  evidence_result = Array(evidence["mappings"]).find { |item| item["id"] == mapping.fetch("id") }
  new_id = mapping.fetch("new_id")
  unless new_id.start_with?("file:")
    failures << "File Mappingのnew_idがFileではありません: #{new_id}"
    next false
  end
  new_path = File.join(root, new_id.delete_prefix("file:"))
  actual_digest = File.file?(new_path) ? sha256.call(new_path) : nil
  valid = mapping.fetch("old_value") == expected_digest && mapping.fetch("new_value") == actual_digest &&
    %w[byte-identical runtime-equivalent].include?(mapping.fetch("proof_type")) &&
    mapping.fetch("reason").length >= 20 && evidence_result && evidence_result["result"] == "pass"
  failures << "MappingまたはMigration Evidenceが不正です: #{old_id}" unless valid
  valid
end

baseline.fetch("immutable_files").each do |record|
  relative = record.fetch("path")
  path = File.join(root, relative)
  next if File.file?(path) && sha256.call(path) == record.fetch("digest")
  valid_mapping.call("file:#{relative}", record.fetch("digest"))
end

coverage = load_yaml.call("coverage.yaml")
current_targets = coverage.fetch("targets").to_h { |target| [target.fetch("id"), target] }
state_rank = {"missing"=>0, "planned"=>1, "partial"=>2, "covered"=>3}
requirement_rank = {"optional"=>0, "recommended"=>1, "required"=>2}
baseline.fetch("targets").each do |old|
  current = current_targets[old.fetch("id")]
  unless current
    failures << "Baseline Targetが削除されています: #{old.fetch("id")}"
    next
  end
  failures << "Baseline Target kindが変更されています: #{old.fetch("id")}" unless current.fetch("kind") == old.fetch("kind")
  failures << "Baseline Target requirementが格下げされています: #{old.fetch("id")}" if requirement_rank.fetch(current.fetch("requirement")) < requirement_rank.fetch(old.fetch("requirement"))
  failures << "Baseline Target stateが格下げされています: #{old.fetch("id")}" if state_rank.fetch(current.fetch("state")) < state_rank.fetch(old.fetch("state"))
  %w[claim_ids evidence_ids].each do |field|
    missing = old.fetch(field) - current.fetch(field)
    failures << "Baseline Target #{old.fetch("id")}から#{field}が削除されています: #{missing.join(",")}" unless missing.empty?
  end
end
forbidden_states = current_targets.values.select { |target| %w[excluded infeasible].include?(target.fetch("state")) }
failures << "excluded/infeasible Targetがあります: #{forbidden_states.map { |target| target.fetch("id") }.join(",")}" unless forbidden_states.empty?

claims = load_yaml.call("atlas/claims/index.yaml").fetch("claims").to_h { |item| [item.fetch("id"), item] }
baseline.fetch("claims").each do |old|
  current = claims[old.fetch("id")]
  if !current
    failures << "Baseline Claimが削除されています: #{old.fetch("id")}"
  elsif current != old
    failures << "Baseline Claimが変更されています: #{old.fetch("id")}"
  end
end
proofs = load_yaml.call("atlas/proof-obligations/index.yaml").fetch("proof_obligations").to_h { |item| [item.fetch("id"), item] }
baseline.fetch("proof_obligations").each do |old|
  current = proofs[old.fetch("id")]
  failures << "Baseline Proofが削除されています: #{old.fetch("id")}" unless current
  failures << "Baseline Proofが変更されています: #{old.fetch("id")}" if current && current != old
end
capabilities = load_yaml.call("atlas/capabilities/index.yaml").fetch("capabilities").to_h { |item| [item.fetch("id"), item] }
baseline.fetch("capabilities").each do |old|
  current = capabilities[old.fetch("id")]
  failures << "Baseline Capabilityが削除されています: #{old.fetch("id")}" unless current
  failures << "Baseline Capabilityが変更されています: #{old.fetch("id")}" if current && current != old
end

evidence = Dir.glob(File.join(root, "evidence/*.evidence.yaml")).map do |path|
  item = YAML.safe_load(File.read(path), aliases: false)
  [item.fetch("id"), item]
end.to_h
baseline.fetch("evidence").each do |old|
  current = evidence[old.fetch("id")]
  failures << "Baseline Evidenceが削除されています: #{old.fetch("id")}" unless current
  failures << "Baseline pass Evidenceが格下げされています: #{old.fetch("id")}" if current && old.fetch("verdict") == "pass" && current.fetch("verdict") != "pass"
end

sources = load_yaml.call("sources.lock.yaml").fetch("sources").to_h { |item| [item.fetch("id"), item] }
baseline.fetch("sources").each do |old|
  current = sources[old.fetch("id")]
  failures << "Baseline Sourceが削除されています: #{old.fetch("id")}" unless current
  %w[kind version digest].each do |field|
    failures << "Baseline Source #{old.fetch("id")}の#{field}が変更されています" if current && current[field] != old[field]
  end
end

baseline.fetch("labs").each do |id|
  run = File.join(root, "labs/#{id}/run.sh")
  failures << "Baseline Labが削除またはdisabled化されています: #{id}" unless File.file?(run) && File.executable?(run)
end
skill_package = load_yaml.call("skill.package.yaml")
minimum = skill_package.fetch("evals").fetch("minimum_pass_rate").to_f
failures << "Skill Eval閾値が縮小されています" if minimum < baseline.dig("skill_eval", "minimum_pass_rate").to_f
current_cases = JSON.parse(File.read(File.join(root, "evals/cases.json"))).map { |item| item.fetch("id") }
missing_cases = baseline.dig("skill_eval", "case_ids") - current_cases
failures << "Baseline Skill Eval Caseが削除されています: #{missing_cases.join(",")}" unless missing_cases.empty?

workflow = load_yaml.call(".github/workflows/ci.yml")
validate_steps = workflow.fetch("jobs").fetch("validate").fetch("steps")
baseline.dig("ci", "required_steps").each do |old|
  failures << "Baseline CI Stepが削除または変更されています: #{old.fetch("name")}" unless validate_steps.any? { |step| step["name"] == old.fetch("name") && step["run"] == old.fetch("run") }
end
current_ci_labs = workflow.fetch("jobs").fetch("executable-labs").fetch("strategy").fetch("matrix").fetch("lab")
missing_ci_labs = baseline.dig("ci", "executable_labs") - current_ci_labs
failures << "Baseline CI Lab Matrixが縮小されています: #{missing_ci_labs.join(",")}" unless missing_ci_labs.empty?
core_ref = validate_steps.find { |step| step.fetch("name", "").include?("reference-atlas-core") }.fetch("with").fetch("ref")
old_core_ref = baseline.dig("ci", "core_ref")
if core_ref != old_core_ref
  mapping = approved_mappings["ci:core-ref:#{old_core_ref}"]
  evidence_path = mapping && File.join(root, mapping.fetch("migration_evidence"))
  evidence_doc = evidence_path && File.file?(evidence_path) ? JSON.parse(File.read(evidence_path)) : {}
  evidence_result = Array(evidence_doc["mappings"]).find { |item| mapping && item["id"] == mapping.fetch("id") }
  valid = mapping && mapping.fetch("new_id") == "ci:core-ref:#{core_ref}" && mapping.fetch("new_value") == core_ref &&
    mapping.fetch("proof_type") == "version-forward-compatible" && mapping.fetch("reason").length >= 20 &&
    evidence_result && evidence_result["result"] == "pass"
  failures << "Core CI refの前方互換Mappingがありません" unless valid
end

report = {
  "schema_version"=>1,
  "atlas_id"=>baseline.fetch("atlas_id"),
  "baseline_commit"=>baseline.fetch("baseline_commit"),
  "baseline_counts"=>baseline.fetch("counts"),
  "current_counts"=>{
    "targets"=>current_targets.length, "capabilities"=>capabilities.length,
    "claims"=>claims.length, "proof_obligations"=>proofs.length,
    "evidence"=>evidence.length, "sources"=>sources.length,
    "labs"=>Dir.glob(File.join(root, "labs/*/run.sh")).length,
    "skill_cases"=>current_cases.length, "ci_labs"=>current_ci_labs.length
  },
  "approved_replacements"=>approved_mappings.keys.sort,
  "failures"=>failures,
  "verdict"=>failures.empty? ? "pass" : "fail"
}
File.write(File.join(root, "evidence/non-regression-audit-report.json"), JSON.pretty_generate(report) + "\n")
unless failures.empty?
  warn failures.map { |failure| "- #{failure}" }.join("\n")
  exit 1
end
puts "Non-regression audit: baseline_targets=#{baseline.dig("counts", "targets")} current_targets=#{current_targets.length} baseline_labs=#{baseline.dig("counts", "labs")} current_labs=#{report.dig("current_counts", "labs")} verdict=pass"
