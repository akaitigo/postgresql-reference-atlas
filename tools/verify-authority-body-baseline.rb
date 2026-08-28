#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("..", __dir__)
baseline = JSON.parse(File.read(File.join(ROOT, "baselines/authority-body-inventory-v1.json")))
migration = JSON.parse(File.read(File.join(ROOT, "migrations/authority-body-inventory-v1.json")))
snapshot = JSON.parse(File.read(File.join(ROOT, "authority/body-inventory.snapshot.json")))
abort "Authority body baseline identityが不正です" unless baseline.fetch("schema_version") == 1 && baseline.fetch("id") == "postgresql-authority-body-inventory-v1-2026-08-28" && migration.fetch("baseline_id") == baseline.fetch("id")
abort "Authority body document/selector floorが縮小しています" unless snapshot.dig("summary", "source_entries") >= baseline.fetch("source_entries") && snapshot.dig("summary", "unique_documents") >= baseline.fetch("unique_documents") && snapshot.fetch("selector_contract") == baseline.fetch("selector_contract")
abort "Authority body baseline tool digestがdriftしています" unless snapshot.fetch("tool_digest") == baseline.fetch("tool_digest")

current_documents = snapshot.fetch("documents").to_h do |record|
  artifact = JSON.parse(File.read(File.join(ROOT, record.fetch("path"))))
  [artifact.fetch("document_id"), [record, artifact]]
end
current_anchor_ids = current_documents.values.flat_map { |_record, artifact| artifact.fetch("anchors").map { |anchor| anchor.fetch("id") } }
abort "Current Authority anchor IDが重複しています" unless current_anchor_ids.uniq.length == current_anchor_ids.length
current_anchor_set = current_anchor_ids.to_h { |id| [id, true] }
baseline_anchor_ids = baseline.fetch("documents").flat_map { |document| document.fetch("anchor_ids") }
abort "Baseline Authority anchor IDが重複しています" unless baseline_anchor_ids.uniq.length == baseline_anchor_ids.length

replacements = migration.fetch("replacements").to_h { |replacement| [replacement.fetch("old_anchor_id"), replacement] }
retained = 0
replaced = 0
baseline.fetch("documents").each do |expected|
  current = current_documents[expected.fetch("id")]
  abort "Authority body baseline documentが削除されています: #{expected.fetch('id')}" unless current
  record, artifact = current
  abort "Authority body baseline document identityがdriftしています: #{expected.fetch('id')}" unless record.fetch("path") == expected.fetch("path") && artifact.fetch("locked_body_digest") == expected.fetch("locked_body_digest") && artifact.fetch("source_ids") == expected.fetch("source_ids")
  expected.fetch("anchor_ids").each do |anchor_id|
    if current_anchor_set[anchor_id]
      retained += 1
    elsif replacements[anchor_id]
      replacement = replacements.fetch(anchor_id)
      abort "Authority anchor replacementが不正です: #{anchor_id}" unless replacement.fetch("new_anchor_ids").any? && replacement.fetch("new_anchor_ids").all? { |new_id| current_anchor_set[new_id] } && replacement.fetch("execution_proof") != replacement.fetch("migration_evidence") && replacement.fetch("reason").length >= 20 && File.file?(File.join(ROOT, replacement.fetch("execution_proof"))) && File.file?(File.join(ROOT, replacement.fetch("migration_evidence")))
      replaced += 1
    else
      abort "Authority body anchorがMappingなしで削除されています: #{anchor_id}"
    end
  end
end
report = {
  "schema_version"=>1, "baseline_id"=>baseline.fetch("id"),
  "baseline_anchors"=>baseline_anchor_ids.length, "current_anchors"=>current_anchor_ids.length,
  "retained"=>retained, "replaced"=>replaced,
  "added"=>current_anchor_ids.length - retained - replacements.values.flat_map { |replacement| replacement.fetch("new_anchor_ids") }.uniq.length,
  "document_floor"=>"#{baseline.fetch('documents').length}/#{current_documents.length}", "status"=>"pass"
}
File.write(File.join(ROOT, "evidence/authority-body-non-regression-report.json"), JSON.pretty_generate(report) + "\n")
puts "Authority body non-regression: retained=#{retained}/#{baseline_anchor_ids.length} replaced=#{replaced} added=#{report.fetch('added')} documents=#{report.fetch('document_floor')}"
