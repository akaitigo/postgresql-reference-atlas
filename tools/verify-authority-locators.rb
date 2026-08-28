#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

ROOT = File.expand_path("..", __dir__)
INDEX_PATH = File.join(ROOT, "authority/locator-extraction.snapshot.json")
FORBIDDEN_FIELDS = %w[body text content excerpt quote snippet html markdown raw payload].freeze
CANDIDATE_KEYS = %w[
  authority_surface_id behavior_id capability_id classification context_digest context_end
  context_start context_unit document_digest document_path locator locator_status reference_url
].sort.freeze

def exact_keys!(object, expected, label)
  actual = object.keys.sort
  abort "#{label}に禁止field、未知field、または欠落があります: #{actual.join(',')}" unless actual == expected.sort
end

def reject_embedded_body!(value, path = "$")
  case value
  when Hash
    value.each do |key, child|
      abort "第三者本文fieldは禁止です: #{path}.#{key}" if FORBIDDEN_FIELDS.include?(key.downcase)
      reject_embedded_body!(child, "#{path}.#{key}")
    end
  when Array
    value.each_with_index { |child, index| reject_embedded_body!(child, "#{path}[#{index}]") }
  end
end

def digest_file(path)
  "sha256:#{Digest::SHA256.file(path).hexdigest}"
end

sources = YAML.safe_load(File.read(File.join(ROOT, "sources.lock.yaml")), aliases: false)
  .fetch("sources").to_h { |source| [source.fetch("id"), source] }
index = JSON.parse(File.read(INDEX_PATH))
reject_embedded_body!(index)
([File.join(ROOT, "authority/extraction.snapshot.json")] + Dir.glob(File.join(ROOT, "authority/surfaces-draft/*.json"))).each do |path|
  reject_embedded_body!(JSON.parse(File.read(path)), path)
end
exact_keys!(index, %w[schema_version atlas_id generated_at status body_storage summary locator_status sources], "Authority locator index")
exact_keys!(index.fetch("summary"), %w[
  authority_artifacts candidate_surfaces source_commit_matched stale_source_bodies
  url_retrieval_deferred locator_evaluations_deferred human_reviewed_surfaces
  generated_surface_candidates_exhaustive authority_text_surfaces_exhaustive
  postgresql_authority_denominator_closed core_v2_eligible_surfaces
], "Authority locator summary")
abort "Authority locator index identityが不正です" unless index.fetch("schema_version") == 1 && index.fetch("atlas_id") == "postgresql-reference-atlas"
abort "Review未完了statusを維持してください" unless index.fetch("status") == "incomplete-human-review-required"
abort "本文保存境界が不正です" unless index.fetch("body_storage") == "digest-and-locator-offset-only"

summary = index.fetch("summary")
abort "生成候補全件とAuthority本文全体を混同しています" unless summary.fetch("generated_surface_candidates_exhaustive") == true && summary.fetch("authority_text_surfaces_exhaustive") == false
abort "Authority denominatorを早期Closureしています" unless summary.fetch("postgresql_authority_denominator_closed") == false
abort "Human review未完了を隠せません" unless summary.fetch("human_reviewed_surfaces") == 0 && summary.fetch("core_v2_eligible_surfaces") == 0

source_records = index.fetch("sources")
abort "Authority artifact indexに重複があります" unless source_records.map { |record| record.fetch("authority_artifact_id") }.uniq.length == source_records.length
actual_files = Dir.glob(File.join(ROOT, "authority/locator-draft/*.json")).sort
expected_files = source_records.map { |record| File.join(ROOT, record.fetch("path")) }.sort
abort "Authority locator artifact集合が一致しません" unless actual_files == expected_files

status_totals = Hash.new(0)
candidate_total = 0
source_records.each do |record|
  exact_keys!(record, %w[authority_artifact_id source_id path digest candidate_surfaces locator_status], "Authority locator source index")
  path = File.join(ROOT, record.fetch("path"))
  abort "Authority locator artifact digestが不正です: #{record.fetch('path')}" unless digest_file(path) == record.fetch("digest")
  artifact = JSON.parse(File.read(path))
  reject_embedded_body!(artifact)
  exact_keys!(artifact, %w[schema_version authority_artifact_id source_id source_url locked_source_digest source_version extraction candidate_surfaces], "Authority locator artifact")
  exact_keys!(artifact.fetch("extraction"), %w[method tool reference_design review_status body_storage source_checkout_commit], "Authority locator extraction")
  exact_keys!(artifact.dig("extraction", "reference_design"), %w[repository commit], "Authority locator reference design")
  abort "FE locator reference commitが不正です" unless artifact.dig("extraction", "reference_design", "commit") == "cabf687bab769b17928d950acc416f3f77eb4ca3"
  abort "Locator artifact review/storage境界が不正です" unless artifact.dig("extraction", "review_status") == "automated-unreviewed" && artifact.dig("extraction", "body_storage") == "digest-and-locator-offset-only"
  source = sources.fetch(artifact.fetch("source_id"))
  abort "Locator artifact source lockが不正です" unless artifact.fetch("source_url") == source.fetch("url") && artifact.fetch("locked_source_digest") == source.fetch("digest") && artifact.fetch("source_version") == source.fetch("version")

  authority_path = File.join(ROOT, "authority/#{artifact.fetch('authority_artifact_id')}.authority-surfaces.json")
  authority = JSON.parse(File.read(authority_path))
  expected_surfaces = authority.fetch("surfaces").to_h { |surface| [surface.fetch("id"), surface] }
  candidates = artifact.fetch("candidate_surfaces")
  abort "Authority locator candidateに欠落または重複があります" unless candidates.length == expected_surfaces.length && candidates.map { |candidate| candidate.fetch("authority_surface_id") }.uniq.length == candidates.length
  candidates.each do |candidate|
    exact_keys!(candidate, CANDIDATE_KEYS, "Authority locator candidate")
    surface = expected_surfaces.fetch(candidate.fetch("authority_surface_id"))
    abort "Authority locator metadataがdriftしています" unless candidate.fetch("capability_id") == surface.fetch("capability_id") && candidate.fetch("behavior_id") == surface.fetch("behavior_id") && candidate.fetch("locator") == surface.fetch("locator")
    abort "Human review未完了を隠せません" unless candidate.fetch("classification") == "candidate-included-unreviewed"
    status = candidate.fetch("locator_status")
    located = %w[file-locator-found fragment-found local-contract-anchor-found local-contract-root url-fetch-deferred-source-correspondence-found].include?(status)
    if located
      abort "Locator offset/digestが欠落しています" unless candidate.fetch("document_path").is_a?(String) && candidate.fetch("document_digest")&.match?(/\Asha256:[a-f0-9]{64}\z/) && candidate.fetch("context_digest")&.match?(/\Asha256:[a-f0-9]{64}\z/) && candidate.fetch("context_start").is_a?(Integer) && candidate.fetch("context_end").is_a?(Integer) && candidate.fetch("context_end") >= candidate.fetch("context_start") && candidate.fetch("context_unit") == "byte"
    else
      abort "本文未評価locatorにcontextを付与できません" unless candidate.fetch("context_start").nil? && candidate.fetch("context_end").nil? && candidate.fetch("context_unit").nil? && candidate.fetch("context_digest").nil?
    end
    status_totals[status] += 1
  end
  expected_status = candidates.group_by { |candidate| candidate.fetch("locator_status") }.sort.to_h { |status, rows| [status, rows.length] }
  abort "Locator status集計が不正です" unless record.fetch("locator_status") == expected_status
  abort "Locator candidate件数が不正です" unless record.fetch("candidate_surfaces") == candidates.length
  candidate_total += candidates.length
end

abort "Authority locator総数がInventoryと一致しません" unless candidate_total == YAML.safe_load(File.read(File.join(ROOT, "surface.inventory.yaml")), aliases: false).fetch("items").length
abort "Authority locator index集計が不正です" unless index.fetch("locator_status") == status_totals.sort.to_h
abort "Authority locator summary件数が不正です" unless summary.fetch("authority_artifacts") == source_records.length && summary.fetch("candidate_surfaces") == candidate_total
deferred = status_totals.select { |status, _| status.include?("deferred") }.values.sum
abort "Deferred件数が不正です" unless summary.fetch("locator_evaluations_deferred") == deferred && summary.fetch("url_retrieval_deferred") == deferred
puts "Verified Authority locators: candidates=#{candidate_total} stale=#{summary.fetch('stale_source_bodies')} deferred=#{deferred} human_reviewed=0 denominator_closed=false"
