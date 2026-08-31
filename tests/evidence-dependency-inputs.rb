#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/evidence_dependency_graph"

def locate(bindings, id)
  bindings.find { |item| item.fetch("id") == id } || abort("missing input group: #{id}")
end

def validate_partition!(bindings)
  scenario = locate(bindings, "harness.scenario-skill-reporting")
  control = locate(bindings, "harness.evidence-dependency-control-plane")
  scenario_members = scenario.fetch("members")
  control_members = control.fetch("members")

  scenario_required = %w[
  evals/run.sh
  evals/cases.json
  tools/rerun-evidence-dependencies.rb
  tools/run-scenario-security-001.rb
  tools/generate-definitive-skill-eval.rb
  tools/generate-scenario-proofs.rb
  tools/generate-scenario-closure-plan.rb
  tools/generate-provenance.rb
  tools/verify-definitive-skill-eval.rb
  tools/lib/atomic_evidence_publisher.rb
  tools/lib/canonical-json.rb
  tools/lib/postgresql-skill-routing.rb
  tools/lib/security_query_catalog_inventory_contract.rb
  tools/lib/security_query_extension_contract.rb
  tools/lib/security_publication_provenance_contract.rb
  tools/lib/security_performance_statistics_contract.rb
  tools/lib/security_published_tranche_contract.rb
  tools/lib/security_next_tranche_contract.rb
  tools/lib/security_runtime_readiness_contract.rb
  tools/lib/security_scenario_tranche.rb
  tools/lib/scenario_closure_plan.rb
  tools/lib/scenario_proofs.rb
].freeze
  scenario_required.each do |path|
    abort "scenario-skill-reporting input is missing required generator dependency: #{path}" unless scenario_members.include?(path)
  end

  control_required = %w[
  tools/generate-evidence-dependency-graph.rb
  tools/lib/evidence_dependency_graph.rb
  tools/lib/tracked_generated_freshness.rb
  tools/test-readonly-generator-command-baseline.rb
  tools/test-tracked-generated-freshness.rb
  tools/verify-generated-output-readonly.rb
  tools/verify-tracked-generated-freshness.rb
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
  control_required.each do |path|
    abort "evidence-dependency-control-plane input is missing required verifier dependency: #{path}" unless control_members.include?(path)
  end

  legacy_members = EvidenceDependencyGraph.files("tools/**/*.rb", "evals/run.sh", "evals/cases.json", ".agents/skills/postgresql-atlas/**/*")
  grouped_members = {}
  bindings.each do |binding|
    binding.fetch("members").each do |member|
      grouped_members[member] ||= []
      grouped_members[member] << binding.fetch("id")
    end
  end
  legacy_members.each do |path|
    groups = grouped_members[path] || []
    abort "legacy scenario/graph member was lost from the partitioned input groups: #{path}" if groups.empty?
  end
  missing_mapping = legacy_members.reject do |path|
    groups = grouped_members.fetch(path)
    groups.include?("harness.scenario-skill-reporting") || groups.include?("harness.evidence-dependency-control-plane")
  end
  abort "legacy scenario/graph members were not mapped into the new input groups: #{missing_mapping.join(', ')}" unless missing_mapping.empty?
end

bindings = EvidenceDependencyGraph.current_input_bindings
validate_partition!(bindings)

missing_group = bindings.reject { |binding| binding.fetch("id") == "harness.evidence-dependency-control-plane" }
begin
  validate_partition!(missing_group)
  abort "missing control-plane group was accepted"
rescue SystemExit => e
  raise unless e.status == 1
end

missing_member = Marshal.load(Marshal.dump(bindings))
control = locate(missing_member, "harness.evidence-dependency-control-plane")
control.fetch("members").delete("tools/lib/evidence_dependency_graph.rb")
begin
  validate_partition!(missing_member)
  abort "control-plane member removal was accepted"
rescue SystemExit => e
  raise unless e.status == 1
end

scenario_missing_member = Marshal.load(Marshal.dump(bindings))
scenario = locate(scenario_missing_member, "harness.scenario-skill-reporting")
scenario.fetch("members").delete("tools/lib/security_scenario_tranche.rb")
begin
  validate_partition!(scenario_missing_member)
  abort "scenario tranche selector member removal was accepted"
rescue SystemExit => e
  raise unless e.status == 1
end

ledger_bindings = bindings.to_h { |binding| [binding.fetch("id"), binding.fetch("digest")] }
stale_bindings = ledger_bindings.dup
stale_bindings["harness.evidence-dependency-control-plane"] = "sha256:#{'0' * 64}"
begin
  EvidenceDependencyGraph.verify_ledger_input_bindings!(stale_bindings, bindings)
  abort "control-plane stale ledger digest was accepted"
rescue RuntimeError => e
  abort e.message unless e.message.include?("harness.evidence-dependency-control-plane")
end

scenario_stale_bindings = ledger_bindings.dup
scenario_stale_bindings["harness.scenario-skill-reporting"] = "sha256:#{'f' * 64}"
begin
  EvidenceDependencyGraph.verify_ledger_input_bindings!(scenario_stale_bindings, bindings)
  abort "scenario-skill-reporting stale ledger digest was accepted"
rescue RuntimeError => e
  abort e.message unless e.message.include?("harness.scenario-skill-reporting")
end

puts "Evidence dependency input contractを検証しました: legacy member set partitioned without shrink; group-removal/member-loss and scenario/control-plane stale-digest fixtures rejected"
