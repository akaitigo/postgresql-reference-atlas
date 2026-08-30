#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/evidence_dependency_graph"

root = EvidenceDependencyGraph::ROOT
base = JSON.parse(File.read(File.join(root, EvidenceDependencyGraph::GRAPH_PATH)))
fixtures = Dir.glob(File.join(root, "fixtures/evidence-dependency/*.json")).sort.map { |path| JSON.parse(File.read(path)) }

fixtures.each do |fixture|
  graph = Marshal.load(Marshal.dump(base))
  case fixture.fetch("id")
  when "changed-input-digest-only"
    graph["inputs"][0]["baseline_digest"] = "sha256:#{'0' * 64}"
    graph["inputs"][0]["observed_at"] = (Time.iso8601(graph.dig("runs", 0, "started_at")) + 1).iso8601
  when "missing-rerun-output"
    graph["runs"][0]["output_ids"].delete(graph.dig("outputs", 0, "id"))
  when "evicted-output"
    path = graph.dig("outputs", 0, "path")
    graph["outputs"].shift
    graph["required_outputs"].delete(path)
  when "shrunk-proof-structure"
    graph["structures"].find { |item| item["kind"] == "scenario-proof-index" }["baseline_digest"] = "sha256:#{'0' * 64}"
  else
    raise "未知のnegative fixtureです: #{fixture.fetch('id')}"
  end
  begin
    EvidenceDependencyGraph.verify!(graph)
    raise "negative fixtureを拒否できませんでした: #{fixture.fetch('id')}"
  rescue RuntimeError => error
    raise "期待した拒否理由ではありません: #{fixture.fetch('id')}: #{error.message}" unless error.message.include?(fixture.fetch("expected_error"))
  end
end
puts "Evidence Dependency Graph negative fixturesを検証しました: #{fixtures.length}/#{fixtures.length} rejected"
