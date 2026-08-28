#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "yaml"

root = File.expand_path("..", __dir__)
load_yaml = ->(path) { YAML.safe_load(File.read(File.join(root, path)), aliases: false) }
failures = []

atlas = load_yaml.call("atlas.yaml")
mastery = load_yaml.call("mastery.yaml")
sources_lock = load_yaml.call("sources.lock.yaml")
coverage = load_yaml.call("coverage.yaml")
skill_package = load_yaml.call("skill.package.yaml")
claims_document = load_yaml.call("atlas/claims/index.yaml")
proofs_document = load_yaml.call("atlas/proof-obligations/index.yaml")
capabilities_document = load_yaml.call("atlas/capabilities/index.yaml")

atlas_id = atlas.fetch("id")
[mastery, sources_lock, coverage, skill_package, claims_document, proofs_document, capabilities_document].each do |document|
  failures << "atlas_idが一致しません" unless document.fetch("atlas_id") == atlas_id
end

failures << "atlas.yamlのMastery参照が不正です" unless atlas.dig("mastery", "manifest") == "mastery.yaml" && atlas.dig("mastery", "contract_version") == "1.0.0"
failures << "Mastery EpochがCoverage Epochと一致しません" unless mastery.fetch("epoch") == coverage.fetch("epoch")

required_outcomes = %w[understand choose build verify operate troubleshoot evolve delegate]
required_surfaces = %w[orientation-scope foundations-mechanics architecture-design implementation-construction testing-verification failure-recovery operations-observability security-privacy-safety performance-capacity-cost compatibility-integration migration-evolution-deprecation decision-comparison provenance-rights agent-skill]
actual_outcomes = mastery.fetch("outcomes").map { |outcome| outcome.fetch("id") }
actual_surfaces = mastery.fetch("surfaces").map { |surface| surface.fetch("id") }
failures << "Mastery Outcomeが8種類の完全集合ではありません" unless actual_outcomes.sort == required_outcomes.sort
failures << "Mastery Surfaceが14種類の完全集合ではありません" unless actual_surfaces.sort == required_surfaces.sort

failures << "statusはincompleteまたはcompleteである必要があります" unless %w[incomplete complete].include?(atlas.fetch("status"))
certificate = File.join(root, atlas.dig("completion", "certificate"))
failures << "incomplete状態でCompletion Certificateを置けません" if atlas.fetch("status") == "incomplete" && File.exist?(certificate)

lock_digest = "sha256:#{Digest::SHA256.file(File.join(root, "sources.lock.yaml")).hexdigest}"
failures << "coverage.yamlのauthority_lock_digestがLockfileと一致しません" unless coverage.fetch("authority_lock_digest") == lock_digest

source_ids = sources_lock.fetch("sources").map { |source| source.fetch("id") }
failures << "Source IDが重複しています" unless source_ids.uniq.length == source_ids.length

target_sets = coverage.fetch("target_sets").map { |target_set| target_set.fetch("id") }
targets = coverage.fetch("targets")
target_ids = targets.map { |target| target.fetch("id") }
failures << "Target IDが重複しています" unless target_ids.uniq.length == target_ids.length
targets.each do |target|
  failures << "未知のTarget Set: #{target.fetch("target_set")}" unless target_sets.include?(target.fetch("target_set"))
end

%w[outcomes surfaces].each do |collection|
  mastery.fetch(collection).each do |item|
    item.fetch("target_sets").each do |target_set|
      failures << "Mastery #{item.fetch("id")}が未知のTarget Set #{target_set}を参照しています" unless target_sets.include?(target_set)
    end
  end
end

sbom_path = atlas.dig("license", "sbom")
failures << "license.sbomがsbom.spdx.jsonを参照していません" unless sbom_path == "sbom.spdx.json"
failures << "参照されたSBOMがありません" unless sbom_path && File.file?(File.join(root, sbom_path))

claims = claims_document.fetch("claims")
claim_ids = claims.map { |claim| claim.fetch("id") }
proof_ids = proofs_document.fetch("proof_obligations").map { |proof| proof.fetch("id") }
failures << "Claim IDが重複しています" unless claim_ids.uniq.length == claim_ids.length
entity_claim_ids = Dir.glob(File.join(root, "claims", "*.claim.yaml")).map do |path|
  YAML.safe_load(File.read(path), aliases: false).fetch("id")
end
failures << "個別Claim実体が集約Claimと一致しません" unless entity_claim_ids.sort == claim_ids.sort

claims.each do |claim|
  claim.fetch("source_ids").each do |source_id|
    failures << "Claim #{claim.fetch("id")}が未知のSource #{source_id}を参照しています" unless source_ids.include?(source_id)
  end
  claim.fetch("proof_obligation_ids").each do |proof_id|
    failures << "Claim #{claim.fetch("id")}が未知のProof #{proof_id}を参照しています" unless proof_ids.include?(proof_id)
  end
end

targets.each do |target|
  target.fetch("claim_ids").each do |claim_id|
    failures << "Target #{target.fetch("id")}が未知のClaim #{claim_id}を参照しています" unless claim_ids.include?(claim_id)
  end
end

capabilities_document.fetch("capabilities").each do |capability|
  failures << "Capability #{capability.fetch("id")}にCoverage Targetがありません" unless target_ids.include?(capability.fetch("id"))
  capability.fetch("claim_ids").each do |claim_id|
    failures << "Capability #{capability.fetch("id")}が未知のClaim #{claim_id}を参照しています" unless claim_ids.include?(claim_id)
  end
end

evidence_records = Dir.glob(File.join(root, "evidence", "*.evidence.yaml")).map do |path|
  [path, YAML.safe_load(File.read(path), aliases: false)]
end
evidence_ids = evidence_records.map { |_path, evidence| evidence.fetch("id") }
failures << "Evidence IDが重複しています" unless evidence_ids.uniq.length == evidence_ids.length

evidence_records.each do |path, evidence|
  evidence.fetch("claim_ids").each do |claim_id|
    failures << "#{File.basename(path)}が未知のClaim #{claim_id}を参照しています" unless claim_ids.include?(claim_id)
  end
  failures << "#{File.basename(path)}のsource_digestが失効しています" unless evidence.fetch("source_digest") == lock_digest
  harness = evidence["harness_path"] && File.join(root, evidence.fetch("harness_path"))
  failures << "#{File.basename(path)}のHarness Manifestがありません" unless harness && File.file?(harness)
  artifact = File.join(root, evidence.dig("artifact", "uri"))
  unless File.file?(artifact)
    failures << "#{File.basename(path)}のArtifactがありません"
    next
  end
  actual_digest = "sha256:#{Digest::SHA256.file(artifact).hexdigest}"
  failures << "#{File.basename(path)}のArtifact Digestが一致しません" unless evidence.dig("artifact", "digest") == actual_digest
end

targets.each do |target|
  target.fetch("evidence_ids").each do |evidence_id|
    failures << "Target #{target.fetch("id")}が未生成Evidence #{evidence_id}を参照しています" unless evidence_ids.include?(evidence_id)
  end
end

unless failures.empty?
  warn failures.map { |failure| "- #{failure}" }.join("\n")
  exit 1
end

puts "Atlas GraphとEvidence Digestの整合を確認しました"
