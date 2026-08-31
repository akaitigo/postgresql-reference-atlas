#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/evidence_dependency_graph"

ledger = JSON.parse(File.read(EvidenceDependencyGraph.absolute(EvidenceDependencyGraph::LEDGER_PATH)))
EvidenceDependencyGraph.verify_ledger_output_bindings!(ledger, require_graph: ARGV.include?("--with-graph"))
phase = ARGV.include?("--with-graph") ? "including final Graph" : "before final Graph"
puts "Full-run generated output bindingsを検証しました: #{ledger.fetch('output_bindings').length} bindings (#{phase})"
