#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SOURCE_ROOT = File.expand_path(ARGV.fetch(0))
OUTPUT_DIR = File.join(ROOT, "authority/locator-draft")
SOURCE_COMMIT = "724edf9bde9d356724ad384a2e196edc3c9f80f7"
GENERATED_AT = "2026-08-28T00:00:00+09:00"

def sha256(value)
  "sha256:#{Digest::SHA256.hexdigest(value)}"
end

def exact_source_commit!
  head, error, status = Open3.capture3("git", "-C", SOURCE_ROOT, "rev-parse", "HEAD")
  abort "PostgreSQL source checkoutを検証できません: #{error.strip}" unless status.success?
  abort "PostgreSQL source commitがLockと一致しません: #{head.strip}" unless head.strip == SOURCE_COMMIT
end

def bounded_line(bytes, offset)
  start_offset = bytes.rindex("\n", [offset - 1, 0].max) || -1
  end_offset = bytes.index("\n", offset) || bytes.bytesize
  [start_offset + 1, [end_offset + 1, bytes.bytesize].min]
end

def located_document(relative_path, anchor: nil, status: "file-locator-found")
  absolute = File.join(SOURCE_ROOT, relative_path)
  return {"locator_status"=>"source-document-not-found", "document_path"=>relative_path} unless File.file?(absolute)

  bytes = File.binread(absolute)
  if anchor
    match = bytes.match(/\bid=["']#{Regexp.escape(anchor)}["']/)
    return {"locator_status"=>"fragment-not-found", "document_path"=>relative_path, "document_digest"=>sha256(bytes)} unless match
    context_start, context_end = bounded_line(bytes, match.begin(0))
    locator_status = status == "url-fetch-deferred-source-correspondence-found" ? status : "fragment-found"
  else
    context_start = 0
    context_end = bytes.bytesize
    locator_status = status
  end
  {
    "locator_status"=>locator_status,
    "document_path"=>relative_path,
    "document_digest"=>sha256(bytes),
    "context_start"=>context_start,
    "context_end"=>context_end,
    "context_unit"=>"byte",
    "context_digest"=>sha256(bytes.byteslice(context_start...context_end))
  }
end

def source_locator(locator)
  relative_path, anchor = locator.split("#", 2)
  located_document(relative_path, anchor: anchor)
end

def docs_sql_locator(locator)
  slug = locator[%r{/sql-([^/]+)\.html(?:\z|[#?])}, 1]
  return {"locator_status"=>"url-fetch-deferred-source-correspondence-not-mapped"} unless slug
  relative_path = $sql_source_by_slug[slug]
  return {"locator_status"=>"url-fetch-deferred-source-correspondence-not-mapped"} unless relative_path
  located_document(relative_path, status: "url-fetch-deferred-source-correspondence-found")
end

def local_contract_locator(locator)
  relative_path, anchor = locator.split("#", 2)
  absolute = File.join(ROOT, relative_path)
  return {"locator_status"=>"local-contract-not-found", "document_path"=>relative_path} unless File.file?(absolute)
  bytes = File.binread(absolute)
  match = anchor && bytes.match(/^\s*-?\s*id:\s*#{Regexp.escape(anchor)}\s*$/)
  start_offset, end_offset = match ? bounded_line(bytes, match.begin(0)) : [0, bytes.bytesize]
  {
    "locator_status"=>match ? "local-contract-anchor-found" : "local-contract-root",
    "document_path"=>relative_path,
    "document_digest"=>sha256(bytes),
    "context_start"=>start_offset,
    "context_end"=>end_offset,
    "context_unit"=>"byte",
    "context_digest"=>sha256(bytes.byteslice(start_offset...end_offset))
  }
end

exact_source_commit!
$sql_source_by_slug = Dir.glob(File.join(SOURCE_ROOT, "doc/src/sgml/ref/*.sgml")).sort.each_with_object({}) do |absolute, index|
  bytes = File.binread(absolute)
  slug = bytes[/<refentry\s+id=["']sql-([^"']+)["']/i, 1]
  index[slug] = absolute.delete_prefix("#{SOURCE_ROOT}/") if slug
end
sources = YAML.safe_load(File.read(File.join(ROOT, "sources.lock.yaml")), aliases: false)
  .fetch("sources").to_h { |source| [source.fetch("id"), source] }
source_lock = sources.fetch("postgresql-source-rel-18.6")
abort "Source lock commitが想定と一致しません" unless source_lock.fetch("version") == SOURCE_COMMIT

FileUtils.mkdir_p(OUTPUT_DIR)
artifact_paths = Dir.glob(File.join(ROOT, "authority/*.authority-surfaces.json")).sort
index_sources = []
totals = Hash.new(0)

artifact_paths.each do |path|
  authority_artifact_id = File.basename(path, ".authority-surfaces.json")
  authority = JSON.parse(File.read(path))
  source = sources.fetch(authority.fetch("source_id"))
  candidates = authority.fetch("surfaces").map do |surface|
    location = case authority_artifact_id
               when "docs-sections", "source-surface" then source_locator(surface.fetch("locator"))
               when "docs-sql" then docs_sql_locator(surface.fetch("locator"))
               when "runtime-catalog" then {"locator_status"=>"runtime-metadata-locator"}
               when "definitive-domain" then local_contract_locator(surface.fetch("locator"))
               else abort "未知のAuthority artifactです: #{authority_artifact_id}"
               end
    totals[location.fetch("locator_status")] += 1
    {
      "authority_surface_id"=>surface.fetch("id"),
      "capability_id"=>surface.fetch("capability_id"),
      "behavior_id"=>surface.fetch("behavior_id"),
      "reference_url"=>source.fetch("url"),
      "locator"=>surface.fetch("locator"),
      "classification"=>"candidate-included-unreviewed"
    }.merge({
      "document_path"=>nil, "document_digest"=>nil,
      "locator_status"=>nil, "context_start"=>nil, "context_end"=>nil,
      "context_unit"=>nil, "context_digest"=>nil
    }).merge(location)
  end
  document = {
    "schema_version"=>1,
    "authority_artifact_id"=>authority_artifact_id,
    "source_id"=>source.fetch("id"),
    "source_url"=>source.fetch("url"),
    "locked_source_digest"=>source.fetch("digest"),
    "source_version"=>source.fetch("version"),
    "extraction"=>{
      "method"=>"locked-source-locator-context-digest",
      "tool"=>"tools/generate-authority-locators.rb",
      "reference_design"=>{
        "repository"=>"frontend-behavior-atlas",
        "commit"=>"cabf687bab769b17928d950acc416f3f77eb4ca3"
      },
      "review_status"=>"automated-unreviewed",
      "body_storage"=>"digest-and-locator-offset-only",
      "source_checkout_commit"=>SOURCE_COMMIT
    },
    "candidate_surfaces"=>candidates
  }
  relative_path = "authority/locator-draft/#{authority_artifact_id}.json"
  output_path = File.join(ROOT, relative_path)
  File.write(output_path, JSON.pretty_generate(document) + "\n")
  index_sources << {
    "authority_artifact_id"=>authority_artifact_id,
    "source_id"=>source.fetch("id"),
    "path"=>relative_path,
    "digest"=>"sha256:#{Digest::SHA256.file(output_path).hexdigest}",
    "candidate_surfaces"=>candidates.length,
    "locator_status"=>candidates.group_by { |candidate| candidate.fetch("locator_status") }
      .sort.to_h { |status, rows| [status, rows.length] }
  }
end

expected_names = artifact_paths.map { |path| "#{File.basename(path, ".authority-surfaces.json")}.json" }.sort
unexpected = Dir.glob(File.join(OUTPUT_DIR, "*.json")).map { |path| File.basename(path) }.sort - expected_names
abort "旧Locator artifactがあります: #{unexpected.join(', ')}" unless unexpected.empty?

candidate_total = index_sources.sum { |item| item.fetch("candidate_surfaces") }
index = {
  "schema_version"=>1,
  "atlas_id"=>"postgresql-reference-atlas",
  "generated_at"=>GENERATED_AT,
  "status"=>"incomplete-human-review-required",
  "body_storage"=>"digest-and-locator-offset-only",
  "summary"=>{
    "authority_artifacts"=>index_sources.length,
    "candidate_surfaces"=>candidate_total,
    "source_commit_matched"=>true,
    "stale_source_bodies"=>0,
    "url_retrieval_deferred"=>totals["url-fetch-deferred-source-correspondence-found"] + totals["url-fetch-deferred-source-correspondence-not-mapped"],
    "locator_evaluations_deferred"=>totals.select { |status, _| status.include?("deferred") }.values.sum,
    "human_reviewed_surfaces"=>0,
    "generated_surface_candidates_exhaustive"=>true,
    "authority_text_surfaces_exhaustive"=>false,
    "postgresql_authority_denominator_closed"=>false,
    "core_v2_eligible_surfaces"=>0
  },
  "locator_status"=>totals.sort.to_h,
  "sources"=>index_sources
}
File.write(File.join(ROOT, "authority/locator-extraction.snapshot.json"), JSON.pretty_generate(index) + "\n")
puts "Authority locator extraction: candidates=#{candidate_total} deferred=#{index.dig('summary', 'locator_evaluations_deferred')} human_reviewed=0 denominator_closed=false"
