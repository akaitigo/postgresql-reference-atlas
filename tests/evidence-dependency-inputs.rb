#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/evidence_dependency_graph"

input = EvidenceDependencyGraph.current_input_bindings.find { |item| item.fetch("id") == "harness.scenario-skill-reporting" }
members = input.fetch("members")

required = %w[
  evals/run.sh
  evals/cases.json
  tools/rerun-evidence-dependencies.rb
  tools/run-scenario-security-001.rb
  tools/generate-definitive-skill-eval.rb
  tools/generate-scenario-proofs.rb
  tools/generate-scenario-closure-plan.rb
  tools/generate-provenance.rb
  tools/generate-evidence-dependency-graph.rb
  tools/verify-definitive-skill-eval.rb
  tools/lib/atomic_evidence_publisher.rb
  tools/lib/canonical-json.rb
  tools/lib/evidence_dependency_graph.rb
  tools/lib/postgresql-skill-routing.rb
  tools/lib/scenario_closure_plan.rb
  tools/lib/scenario_proofs.rb
].freeze
required.each do |path|
  abort "scenario-skill-reporting input is missing required generator dependency: #{path}" unless members.include?(path)
end

forbidden = %w[
  tests/evidence-dependency-inputs.rb
  tests/workflow-action-pins.rb
].freeze
unexpected = forbidden.select { |path| members.include?(path) }
abort "scenario-skill-reporting input includes gate-only verifier/test files: #{unexpected.join(', ')}" unless unexpected.empty?

puts "Evidence dependency input contractを検証しました: scenario-skill-reporting excludes moved gate-only tests"
