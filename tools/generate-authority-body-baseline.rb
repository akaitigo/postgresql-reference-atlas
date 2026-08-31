#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("..", __dir__)
snapshot = JSON.parse(File.read(File.join(ROOT, "authority/body-inventory.snapshot.json")))
documents = snapshot.fetch("documents").map do |record|
  artifact = JSON.parse(File.read(File.join(ROOT, record.fetch("path"))))
  {
    "id"=>artifact.fetch("document_id"), "path"=>record.fetch("path"),
    "locked_body_digest"=>artifact.fetch("locked_body_digest"), "source_ids"=>artifact.fetch("source_ids"),
    "anchor_ids"=>artifact.fetch("anchors").map { |anchor| anchor.fetch("id") }.sort
  }
end.sort_by { |document| document.fetch("id") }
baseline = {
  "schema_version"=>1, "id"=>"postgresql-authority-body-inventory-v1-2026-08-28",
  "captured_at"=>"2026-08-28T00:00:00+09:00", "tool_digest"=>snapshot.fetch("tool_digest"),
  "source_entries"=>snapshot.dig("summary", "source_entries"),
  "unique_documents"=>snapshot.dig("summary", "unique_documents"),
  "selector_contract"=>snapshot.fetch("selector_contract"), "documents"=>documents
}
File.write(File.join(ROOT, "baselines/authority-body-inventory-v1.json"), JSON.pretty_generate(baseline) + "\n")
puts "Authority body baseline generated: documents=#{documents.length} anchors=#{documents.sum { |document| document.fetch('anchor_ids').length }}"
