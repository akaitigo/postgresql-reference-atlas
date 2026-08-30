#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/evidence_dependency_graph"

document = EvidenceDependencyGraph.build
path = EvidenceDependencyGraph.absolute(EvidenceDependencyGraph::GRAPH_PATH)
File.write(path, JSON.pretty_generate(document) + "\n")
puts "Evidence Dependency Graphを生成しました: inputs=#{document.fetch('inputs').length} outputs=#{document.fetch('outputs').length} runs=#{document.fetch('runs').length}"
