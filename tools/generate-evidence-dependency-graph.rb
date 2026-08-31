#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/evidence_dependency_graph"

document = EvidenceDependencyGraph.build
path = EvidenceDependencyGraph.absolute(EvidenceDependencyGraph::GRAPH_PATH)
bytes = JSON.pretty_generate(document) + "\n"
ledger_path = EvidenceDependencyGraph.absolute(EvidenceDependencyGraph::LEDGER_PATH)
ledger = JSON.parse(File.read(ledger_path))
bindings = Array(ledger["output_bindings"]).reject do |binding|
  binding.fetch("path") == EvidenceDependencyGraph::GRAPH_PATH
end
bindings << {
  "path"=>EvidenceDependencyGraph::GRAPH_PATH,
  "digest"=>"sha256:#{Digest::SHA256.hexdigest(bytes)}"
}
ledger["output_bindings"] = bindings.sort_by { |binding| binding.fetch("path") }
ledger["output_binding_phase"] = "final-graph-bound"

ledger_bytes = JSON.pretty_generate(ledger) + "\n"
backups = {ledger_path=>File.binread(ledger_path), path=>(File.binread(path) if File.file?(path))}
begin
  [[ledger_path, ledger_bytes], [path, bytes]].each do |destination, content|
    temporary = "#{destination}.staging-#{Process.pid}"
    File.binwrite(temporary, content)
    File.rename(temporary, destination)
  end
rescue StandardError
  backups.each do |destination, content|
    content ? File.binwrite(destination, content) : File.delete(destination) if File.exist?(destination)
  end
  raise
ensure
  Dir.glob("#{ledger_path}.staging-*", File::FNM_DOTMATCH).each { |temporary| File.delete(temporary) }
  Dir.glob("#{path}.staging-*", File::FNM_DOTMATCH).each { |temporary| File.delete(temporary) }
end
puts "Evidence Dependency Graphを生成しました: inputs=#{document.fetch('inputs').length} outputs=#{document.fetch('outputs').length} runs=#{document.fetch('runs').length}"
