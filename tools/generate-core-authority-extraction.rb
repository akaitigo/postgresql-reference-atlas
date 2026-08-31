#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "yaml"

ROOT = File.expand_path("..", __dir__)
OUTPUT_DIR = File.join(ROOT, "authority/surfaces-draft")

def sha256(value)
  "sha256:#{Digest::SHA256.hexdigest(value)}"
end

sources = YAML.safe_load(File.read(File.join(ROOT, "sources.lock.yaml")), aliases: false).fetch("sources")
FileUtils.mkdir_p(OUTPUT_DIR)
index_sources = []

sources.sort_by { |source| source.fetch("id") }.each do |source|
  source_id = source.fetch("id")
  pattern_slug = source_id.gsub(/[^a-z0-9-]+/, "-")
  edge = {
    "edge_id"=>"edge.authority.#{source_id}",
    "source_id"=>source_id,
    "reference_url"=>source.fetch("url"),
    "locator"=>"document-root",
    "pattern_id"=>"authority/#{pattern_slug}",
    "pattern_kind"=>"systemic",
    "candidate_behavior_id"=>"candidate.authority.#{source_id}",
    "capability_id"=>"foundation.authority-lock",
    "target_id"=>"foundation.authority-lock",
    "claim_id"=>"foundation.authority-lock",
    "variant_ids"=>["variant.authority.#{pattern_slug}.locked-root"],
    "surface_ids"=>%w[orientation-scope provenance-rights testing-verification],
    "classification_basis"=>"domain-contract-projection-unreviewed",
    "domain_reference_metadata_digest"=>sha256(JSON.generate({"id"=>source_id, "url"=>source.fetch("url"), "kind"=>source.fetch("kind"), "version"=>source.fetch("version")})),
    "locator_status"=>"not-evaluated-fetch-failed",
    "context_digest"=>nil,
    "context_start"=>nil,
    "context_end"=>nil,
    "context_unit"=>nil,
    "heading_digest"=>nil,
    "classification"=>"candidate-included-unreviewed"
  }
  draft = {
    "schema_version"=>1,
    "source_id"=>source_id,
    "source_url"=>source.fetch("url"),
    "locked_source_digest"=>source.fetch("digest"),
    "fetch"=>{
      "status"=>"failed",
      "fetched_digest"=>nil,
      "locked_digest_match"=>false,
      "http_status"=>nil,
      "final_url"=>nil,
      "content_type"=>nil,
      "fetched_bytes"=>nil,
      "error_digest"=>sha256("offline-authority-body-retrieval-not-performed:#{source_id}")
    },
    "extraction"=>{
      "method"=>"locked-body-locator-context-digest",
      "tool"=>"tools/generate-core-authority-extraction.rb",
      "review_status"=>"automated-unreviewed",
      "body_storage"=>"digest-and-locator-context-digest-only"
    },
    "candidate_surfaces"=>[edge]
  }
  relative = "authority/surfaces-draft/#{source_id}.json"
  absolute = File.join(ROOT, relative)
  File.write(absolute, JSON.pretty_generate(draft) + "\n")
  index_sources << {
    "id"=>source_id,
    "path"=>relative,
    "digest"=>"sha256:#{Digest::SHA256.file(absolute).hexdigest}",
    "locked_digest_match"=>false,
    "candidate_surfaces"=>1,
    "locator_status"=>{"not-evaluated-fetch-failed"=>1}
  }
end

expected = sources.map { |source| "#{source.fetch('id')}.json" }.sort
actual = Dir.glob(File.join(OUTPUT_DIR, "*.json")).map { |path| File.basename(path) }.sort
abort "Core Authority Draft集合がSource Lockと一致しません" unless actual == expected
input_digest = sha256(JSON.generate(sources.sort_by { |source| source.fetch("id") }.map { |source| source.slice("id", "url", "version", "digest") }))
snapshot = {
  "schema_version"=>1,
  "atlas_id"=>"postgresql-reference-atlas",
  "generated_at"=>"2026-08-28T00:00:00+09:00",
  "status"=>"incomplete-human-review-required",
  "input_digest"=>input_digest,
  "body_storage"=>"digest-and-locator-context-digest-only",
  "summary"=>{
    "locked_sources"=>sources.length,
    "fetched_digest_matched"=>0,
    "fetched_digest_stale"=>0,
    "fetch_failed"=>sources.length,
    "candidate_surfaces"=>sources.length,
    "root_locators"=>0,
    "fragments_found"=>0,
    "fragments_not_found"=>0,
    "locator_evaluations_deferred"=>sources.length,
    "reference_edges_classified"=>sources.length,
    "unclassified_reference_edges"=>0,
    "authority_text_surfaces_exhaustive"=>false,
    "human_reviewed_surfaces"=>0,
    "core_v2_eligible_surfaces"=>0
  },
  "sources"=>index_sources
}
File.write(File.join(ROOT, "authority/extraction.snapshot.json"), JSON.pretty_generate(snapshot) + "\n")
puts "Core Authority extraction: sources=#{sources.length} failed=#{sources.length} deferred=#{sources.length} human_reviewed=0 denominator_closed=false"
