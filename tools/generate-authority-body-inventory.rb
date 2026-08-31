#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SOURCE_ROOT = File.expand_path(ARGV.fetch(0))
SOURCE_COMMIT = "724edf9bde9d356724ad384a2e196edc3c9f80f7"
GENERATED_AT = "2026-08-28T00:00:00+09:00"
SELECTOR_CONTRACT = %w[document-root sgml-id-attribute].freeze
OUTPUT_DIR = File.join(ROOT, "authority/body-inventory-draft")
TOOL_FILES = %w[tools/generate-authority-body-inventory.rb tools/verify-authority-body-inventory.rb].freeze

def sha256(value)
  "sha256:#{Digest::SHA256.hexdigest(value)}"
end

def tool_digest
  sha256(TOOL_FILES.map { |relative| "#{relative}\0#{File.binread(File.join(ROOT, relative))}" }.join("\0"))
end

def document_id(source_id, locator)
  "document-pg-#{Digest::SHA256.hexdigest("#{source_id}\0#{locator}")[0, 16]}"
end

def anchor_id(document_id, body_digest, selector, locator, offset)
  "anchor-pg-#{Digest::SHA256.hexdigest([document_id, body_digest, selector, locator, offset].join("\0"))[0, 20]}"
end

def line_bounds(bytes, offset)
  start_offset = bytes.rindex("\n", [offset - 1, 0].max) || -1
  end_offset = bytes.index("\n", offset) || bytes.bytesize
  [start_offset + 1, [end_offset + 1, bytes.bytesize].min]
end

def extract_anchors(document_id_value, bytes, body_digest)
  root_id = anchor_id(document_id_value, body_digest, "document-root", "document-root", 0)
  anchors = [{
    "id"=>root_id, "locator"=>"document-root", "locator_kind"=>"document-root",
    "raw_selector"=>"document-root", "element_name"=>"document",
    "parent_anchor_id"=>nil, "context_start"=>0, "context_end"=>bytes.bytesize,
    "context_unit"=>"byte", "context_digest"=>body_digest,
    "classification_status"=>"pending-human", "surface_ids"=>[], "behavior_ids"=>[]
  }]
  matcher = /<([A-Za-z][A-Za-z0-9:_-]*)\b[^>]*\b(?:xml:)?id\s*=\s*(["'])([^"']+)\2[^>]*>/im
  bytes.to_enum(:scan, matcher).each do
    match = Regexp.last_match
    element = match[1].downcase
    raw_id = match[3]
    start_offset, end_offset = line_bounds(bytes, match.begin(0))
    locator = "##{raw_id}"
    anchors << {
      "id"=>anchor_id(document_id_value, body_digest, "sgml-id-attribute", locator, match.begin(0)),
      "locator"=>locator, "locator_kind"=>"fragment", "raw_selector"=>"sgml-id-attribute",
      "element_name"=>element, "parent_anchor_id"=>root_id,
      "context_start"=>start_offset, "context_end"=>end_offset, "context_unit"=>"byte",
      "context_digest"=>sha256(bytes.byteslice(start_offset...end_offset)),
      "classification_status"=>"pending-human", "surface_ids"=>[], "behavior_ids"=>[]
    }
  end
  anchors
end

head, error, status = Open3.capture3("git", "-C", SOURCE_ROOT, "rev-parse", "HEAD")
abort "PostgreSQL source checkoutを検証できません: #{error.strip}" unless status.success?
abort "PostgreSQL source commitがLockと一致しません: #{head.strip}" unless head.strip == SOURCE_COMMIT

sources = YAML.safe_load(File.read(File.join(ROOT, "sources.lock.yaml")), aliases: false).fetch("sources")
source_by_id = sources.to_h { |source| [source.fetch("id"), source] }
source_lock = source_by_id.fetch("postgresql-source-rel-18.6")
abort "PostgreSQL source lock commitがdriftしています" unless source_lock.fetch("version") == SOURCE_COMMIT
tool_digest_value = tool_digest
FileUtils.mkdir_p(OUTPUT_DIR)

documents = []
Dir.glob(File.join(SOURCE_ROOT, "doc/src/sgml/**/*.sgml")).sort.each do |absolute|
  relative = absolute.delete_prefix("#{SOURCE_ROOT}/")
  bytes = File.binread(absolute)
  body_digest = sha256(bytes)
  id = document_id(source_lock.fetch("id"), relative)
  documents << {
    "document_id"=>id, "source_ids"=>[source_lock.fetch("id")],
    "authority_url"=>source_lock.fetch("url"), "document_locator"=>"git:#{SOURCE_COMMIT}:#{relative}",
    "locked_source_digest"=>source_lock.fetch("digest"), "locked_body_digest"=>body_digest,
    "fetch"=>{"status"=>"matched", "fetched_digest"=>body_digest, "locked_digest_match"=>true,
               "error_digest"=>nil},
    "anchors"=>extract_anchors(id, bytes, body_digest)
  }
end

license_source = source_by_id.fetch("postgresql-license-rel-18.6")
license_bytes = File.binread(File.join(SOURCE_ROOT, "COPYRIGHT"))
license_digest = sha256(license_bytes)
abort "COPYRIGHT digestがSource Lockと一致しません" unless license_digest == license_source.fetch("digest")
license_id = document_id(license_source.fetch("id"), "COPYRIGHT")
documents << {
  "document_id"=>license_id, "source_ids"=>[license_source.fetch("id")],
  "authority_url"=>license_source.fetch("url"), "document_locator"=>"git:#{SOURCE_COMMIT}:COPYRIGHT",
  "locked_source_digest"=>license_source.fetch("digest"), "locked_body_digest"=>license_digest,
  "fetch"=>{"status"=>"matched", "fetched_digest"=>license_digest, "locked_digest_match"=>true,
             "error_digest"=>nil},
  "anchors"=>extract_anchors(license_id, license_bytes, license_digest)
}

(sources.map { |source| source.fetch("id") } - %w[postgresql-source-rel-18.6 postgresql-license-rel-18.6]).sort.each do |source_id|
  source = source_by_id.fetch(source_id)
  id = document_id(source_id, source.fetch("url"))
  documents << {
    "document_id"=>id, "source_ids"=>[source_id], "authority_url"=>source.fetch("url"),
    "document_locator"=>source.fetch("url"), "locked_source_digest"=>source.fetch("digest"),
    "locked_body_digest"=>source.fetch("digest"),
    "fetch"=>{"status"=>"failed", "fetched_digest"=>nil, "locked_digest_match"=>false,
               "error_digest"=>sha256("authority-body-retrieval-not-performed:#{source_id}")},
    "anchors"=>[]
  }
end

documents.sort_by! { |document| document.fetch("document_id") }
index_records = []
status_counts = Hash.new(0)
selector_counts = Hash.new(0)
documents.each do |document|
  anchors = document.delete("anchors")
  status_counts[document.dig("fetch", "status")] += 1
  anchors.each { |anchor| selector_counts[anchor.fetch("raw_selector")] += 1 }
  artifact = document.merge({
    "schema_version"=>1,
    "extraction"=>{
      "method"=>"sgml-raw-anchor-selector-v1",
      "tool"=>"postgresql-reference-atlas-authority-body-inventory-v1",
      "tool_digest"=>tool_digest_value, "selector_contract"=>SELECTOR_CONTRACT,
      "selector_exhaustive_for_locked_body"=>document.dig("fetch", "status") == "matched",
      "authority_semantics_exhaustive"=>false, "review_status"=>"automated-unreviewed",
      "body_storage"=>"digest-locator-and-offset-only"
    },
    "anchors"=>anchors
  })
  relative_path = "authority/body-inventory-draft/#{document.fetch('document_id')}.json"
  output_path = File.join(ROOT, relative_path)
  File.write(output_path, JSON.pretty_generate(artifact) + "\n")
  index_records << {
    "id"=>document.fetch("document_id"), "path"=>relative_path,
    "digest"=>"sha256:#{Digest::SHA256.file(output_path).hexdigest}",
    "fetch_status"=>document.dig("fetch", "status"), "source_entries"=>document.fetch("source_ids").length,
    "anchors"=>anchors.length,
    "anchors_by_selector"=>anchors.group_by { |anchor| anchor.fetch("raw_selector") }.sort.to_h { |selector, rows| [selector, rows.length] }
  }
end

expected_files = documents.map { |document| "#{document.fetch('document_id')}.json" }.sort
actual_files = Dir.glob(File.join(OUTPUT_DIR, "*.json")).map { |path| File.basename(path) }.sort
abort "Authority body artifact集合がDocument集合と一致しません" unless actual_files == expected_files

input_digest = sha256(JSON.generate({
  "tool_digest"=>tool_digest_value, "source_commit"=>SOURCE_COMMIT,
  "sources"=>sources.map { |source| source.slice("id", "url", "version", "digest") }.sort_by { |source| source.fetch("id") },
  "documents"=>index_records.map { |record| record.slice("id", "fetch_status", "source_entries") }
}))
anchor_total = index_records.sum { |record| record.fetch("anchors") }
snapshot = {
  "schema_version"=>1, "atlas_id"=>"postgresql-reference-atlas", "generated_at"=>GENERATED_AT,
  "status"=>"incomplete-human-review-required", "input_digest"=>input_digest,
  "tool_digest"=>tool_digest_value, "body_storage"=>"digest-locator-and-offset-only",
  "selector_contract"=>SELECTOR_CONTRACT,
  "reference_design"=>{
    "repository"=>"frontend-behavior-atlas", "commit"=>"841ec2fa399606a10305021a8bcd396713b8cee5",
    "absolute_counts_transplanted"=>false
  },
  "summary"=>{
    "source_entries"=>sources.length, "unique_documents"=>documents.length,
    "matched_documents"=>status_counts["matched"], "stale_documents"=>status_counts["stale"],
    "failed_documents"=>status_counts["failed"], "selector_exhaustive_documents"=>status_counts["matched"],
    "raw_anchor_candidates"=>anchor_total, "anchors_by_selector"=>selector_counts.sort.to_h,
    "pending_human_anchors"=>anchor_total, "human_reviewed_anchors"=>0,
    "promoted_surface_artifacts"=>0, "promoted_atomic_behaviors"=>0,
    "authority_semantics_exhaustive"=>false, "postgresql_authority_denominator_closed"=>false
  },
  "documents"=>index_records
}
File.write(File.join(ROOT, "authority/body-inventory.snapshot.json"), JSON.pretty_generate(snapshot) + "\n")
puts "Authority body inventory: documents=#{documents.length} matched=#{status_counts['matched']} stale=#{status_counts['stale']} failed=#{status_counts['failed']} raw_anchors=#{anchor_total} pending_human=#{anchor_total} promoted=0"
