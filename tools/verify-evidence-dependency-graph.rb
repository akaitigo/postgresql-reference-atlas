#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/evidence_dependency_graph"

graph = JSON.parse(File.read(EvidenceDependencyGraph.absolute(EvidenceDependencyGraph::GRAPH_PATH)))
EvidenceDependencyGraph.verify!(graph)
changed = graph.fetch("inputs").count { |input| input.fetch("baseline_digest") != input.fetch("current_digest") }
puts "Evidence Dependency Graphを検証しました: inputs=#{graph.fetch('inputs').length} outputs=#{graph.fetch('outputs').length} changed_inputs=#{changed} first_attempt_runs=#{graph.fetch('runs').length}"
