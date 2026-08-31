#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

require_relative "lib/evidence_dependency_graph"

root = EvidenceDependencyGraph::ROOT
failures = []
diagnostic = "artifacts/pattern-scenario-failures/security-001-20260830T214437Z-8458__closure.unknown.security.json"
graph_path = "evidence/dependency-graph.json"
ledger_relative = EvidenceDependencyGraph::LEDGER_PATH
scenario_input = "harness.scenario-skill-reporting"
control_plane_input = "harness.evidence-dependency-control-plane"

Dir.mktmpdir("pgra-refresh-output-bindings.") do |tmp|
  clone = File.join(tmp, "clone")
  FileUtils.mkdir_p(clone)
  Dir.children(root).each do |entry|
    next if %w[.git .cache].include?(entry)

    FileUtils.cp_r(File.join(root, entry), clone, preserve: true)
  end

  Dir.chdir(clone) do
    ledger_path = File.join(clone, ledger_relative)
    ledger = JSON.parse(File.read(ledger_path))
    ledger.fetch("output_bindings").reject! { |binding| binding.fetch("path") == diagnostic }
    File.write(ledger_path, JSON.pretty_generate(ledger) + "\n")

    stdout, stderr, status = Open3.capture3("ruby", "tools/verify-evidence-output-bindings.rb", chdir: clone)
    failures << "ledger output verifier accepted omitted append-only diagnostic" if status.success?
    output = [stdout, stderr].reject(&:empty?).join
    unless output.include?("Generated output bindingが不足しています: #{diagnostic}")
      failures << "unexpected omission error: #{output}"
    end

    stdout, stderr, status = Open3.capture3("ruby", "tools/refresh-evidence-output-bindings.rb", chdir: clone)
    failures << "refresh command failed: #{stderr.empty? ? stdout : stderr}" unless status.success?
    refreshed = JSON.parse(File.read(ledger_path))
    bindings = refreshed.fetch("output_bindings").to_h { |item| [item.fetch("path"), item.fetch("digest")] }
    failures << "refresh did not restore append-only diagnostic binding" unless bindings.key?(diagnostic)
    failures << "refresh kept final graph binding before graph generation" if bindings.key?(graph_path)
    failures << "refresh phase drifted" unless refreshed["output_binding_phase"] == "tracked-generators-bound"
    input_bindings = refreshed.fetch("input_bindings").to_h { |item| [item.fetch("input_id"), item.fetch("digest")] }
    failures << "refresh did not preserve scenario input binding" unless input_bindings.key?(scenario_input)
    failures << "refresh did not preserve control-plane input binding" unless input_bindings.key?(control_plane_input)
    failures << "refresh context missing" unless refreshed.dig("refresh_context", "kind") == "published-output-binding-refresh"
    stdout, stderr, status = Open3.capture3("ruby", "tools/verify-evidence-output-bindings.rb", chdir: clone)
    failures << "refreshed ledger did not verify: #{[stdout, stderr].reject(&:empty?).join}" unless status.success?

    control = JSON.parse(File.read(ledger_path))
    control.fetch("input_bindings").map! do |item|
      next item unless item.fetch("input_id") == "source.contract-and-authority"

      item.merge("digest"=>"sha256:#{'0' * 64}")
    end
    File.write(ledger_path, JSON.pretty_generate(control) + "\n")
    stdout, stderr, status = Open3.capture3("ruby", "tools/refresh-evidence-output-bindings.rb", chdir: clone)
    failures << "refresh accepted unexpected input drift" if status.success?
    output = [stdout, stderr].reject(&:empty?).join
    unless output.include?("Full rerunなしで再結束できない入力driftがあります: source.contract-and-authority")
      failures << "unexpected input drift rejection message missing: #{output}"
    end
  end
end

abort failures.join("\n") unless failures.empty?
puts "Refreshed output bindings contractを検証しました: append-only diagnostics rebound, allowed input drift only, final graph excluded pre-generation"
