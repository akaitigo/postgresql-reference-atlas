#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

source_root = File.expand_path(ARGV.fetch(0))
baseline_commit = ARGV.fetch(1)
output = File.expand_path(ARGV.fetch(2))

load_yaml = ->(relative) { YAML.safe_load(File.read(File.join(source_root, relative)), aliases: false) }
digest = ->(path) { "sha256:#{Digest::SHA256.file(path).hexdigest}" }
proof_prefixes = %w[
  .agents/skills atlas/capabilities atlas/claims atlas/proof-obligations claims environments
  evals evidence labs operations scripts surface versions
]
proof_files = proof_prefixes.flat_map do |prefix|
  Dir.glob(File.join(source_root, prefix, "**/*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
end
%w[mastery.yaml skill.package.yaml sources.lock.yaml].each { |relative| proof_files << File.join(source_root, relative) }
proof_files.uniq!
structured_indexes = %w[
  atlas/capabilities/index.yaml atlas/claims/index.yaml atlas/proof-obligations/index.yaml
]
proof_files.reject! { |path| structured_indexes.include?(path.delete_prefix("#{source_root}/")) }
proof_files.sort!

coverage = load_yaml.call("coverage.yaml")
claims_index = load_yaml.call("atlas/claims/index.yaml")
proofs_index = load_yaml.call("atlas/proof-obligations/index.yaml")
capabilities_index = load_yaml.call("atlas/capabilities/index.yaml")
sources = load_yaml.call("sources.lock.yaml")
skill_package = load_yaml.call("skill.package.yaml")
skill_cases = JSON.parse(File.read(File.join(source_root, "evals/cases.json")))
workflow = load_yaml.call(".github/workflows/ci.yml")
ci_validate = workflow.fetch("jobs").fetch("validate")
ci_labs = workflow.fetch("jobs").fetch("executable-labs")

claim_entities = Dir.glob(File.join(source_root, "claims/*.claim.yaml")).sort.map do |path|
  claim = YAML.safe_load(File.read(path), aliases: false)
  {"id"=>claim.fetch("id"), "path"=>path.delete_prefix("#{source_root}/"), "digest"=>digest.call(path)}
end
evidence_entities = Dir.glob(File.join(source_root, "evidence/*.evidence.yaml")).sort.map do |path|
  evidence = YAML.safe_load(File.read(path), aliases: false)
  {"id"=>evidence.fetch("id"), "path"=>path.delete_prefix("#{source_root}/"), "digest"=>digest.call(path), "verdict"=>evidence.fetch("verdict")}
end

baseline = {
  "schema_version"=>1,
  "atlas_id"=>"postgresql-reference-atlas",
  "baseline_commit"=>baseline_commit,
  "classification"=>"published-main-non-regression",
  "policy"=>{
    "removal"=>"forbidden",
    "weakening"=>"forbidden",
    "replacement"=>"mapping-plus-equivalent-runtime-proof-plus-migration-evidence"
  },
  "immutable_files"=>proof_files.map { |path| {"path"=>path.delete_prefix("#{source_root}/"), "digest"=>digest.call(path)} },
  "targets"=>coverage.fetch("targets").map do |target|
    target.slice("id", "kind", "requirement", "state", "claim_ids", "evidence_ids")
  end,
  "capabilities"=>capabilities_index.fetch("capabilities"),
  "claims"=>claims_index.fetch("claims"),
  "claim_entities"=>claim_entities,
  "proof_obligations"=>proofs_index.fetch("proof_obligations"),
  "evidence"=>evidence_entities,
  "sources"=>sources.fetch("sources").map { |source| source.slice("id", "kind", "version", "digest") },
  "labs"=>Dir.glob(File.join(source_root, "labs/*/run.sh")).sort.map { |path| File.basename(File.dirname(path)) },
  "skill_eval"=>{
    "minimum_pass_rate"=>skill_package.fetch("evals").fetch("minimum_pass_rate"),
    "case_ids"=>skill_cases.map { |item| item.fetch("id") }
  },
  "ci"=>{
    "required_steps"=>ci_validate.fetch("steps").select { |step| step.key?("run") }.map { |step| step.slice("name", "run") },
    "executable_labs"=>ci_labs.fetch("strategy").fetch("matrix").fetch("lab"),
    "core_ref"=>ci_validate.fetch("steps").find { |step| step.fetch("name", "").include?("reference-atlas-core") }.fetch("with").fetch("ref")
  },
  "counts"=>{
    "targets"=>coverage.fetch("targets").length,
    "capabilities"=>capabilities_index.fetch("capabilities").length,
    "claims"=>claims_index.fetch("claims").length,
    "claim_entities"=>claim_entities.length,
    "proof_obligations"=>proofs_index.fetch("proof_obligations").length,
    "evidence"=>evidence_entities.length,
    "sources"=>sources.fetch("sources").length,
    "labs"=>Dir.glob(File.join(source_root, "labs/*/run.sh")).length,
    "skill_cases"=>skill_cases.length,
    "ci_labs"=>ci_labs.fetch("strategy").fetch("matrix").fetch("lab").length
  }
}

File.write(output, JSON.pretty_generate(baseline) + "\n")
puts "Non-regression baseline: #{baseline.fetch("counts").map { |key, value| "#{key}=#{value}" }.join(" ")}"
