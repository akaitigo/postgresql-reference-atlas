#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SOURCE_ROOT = ARGV[0] && File.expand_path(ARGV[0])
SOURCE_COMMIT = "724edf9bde9d356724ad384a2e196edc3c9f80f7"
SELECTORS = %w[document-root sgml-id-attribute].freeze
TOOL_FILES = %w[tools/generate-authority-body-inventory.rb tools/verify-authority-body-inventory.rb].freeze
FORBIDDEN_FIELDS = %w[body text content excerpt quote snippet html markdown raw payload].freeze

def sha256(value)
  "sha256:#{Digest::SHA256.hexdigest(value)}"
end

def exact_keys!(object, keys, label)
  abort "#{label}のfield集合が不正です: #{object.keys.sort.join(',')}" unless object.keys.sort == keys.sort
end

def reject_body_fields!(value, path = "$")
  case value
  when Hash
    value.each do |key, child|
      abort "第三者本文fieldは禁止です: #{path}.#{key}" if FORBIDDEN_FIELDS.include?(key.downcase)
      reject_body_fields!(child, "#{path}.#{key}")
    end
  when Array
    value.each_with_index { |child, index| reject_body_fields!(child, "#{path}[#{index}]") }
  end
end

snapshot_path = File.join(ROOT, "authority/body-inventory.snapshot.json")
snapshot = JSON.parse(File.read(snapshot_path))
reject_body_fields!(snapshot)
exact_keys!(snapshot, %w[schema_version atlas_id generated_at status input_digest tool_digest body_storage selector_contract reference_design summary documents], "Authority body snapshot")
exact_keys!(snapshot.fetch("summary"), %w[source_entries unique_documents matched_documents stale_documents failed_documents selector_exhaustive_documents raw_anchor_candidates anchors_by_selector pending_human_anchors human_reviewed_anchors promoted_surface_artifacts promoted_atomic_behaviors authority_semantics_exhaustive postgresql_authority_denominator_closed], "Authority body summary")
abort "Authority body snapshot identityが不正です" unless snapshot.fetch("schema_version") == 1 && snapshot.fetch("atlas_id") == "postgresql-reference-atlas" && snapshot.fetch("status") == "incomplete-human-review-required"
abort "Authority body保存境界が不正です" unless snapshot.fetch("body_storage") == "digest-locator-and-offset-only" && snapshot.fetch("selector_contract") == SELECTORS
abort "FE denominator referenceが不正です" unless snapshot.dig("reference_design", "commit") == "841ec2fa399606a10305021a8bcd396713b8cee5" && snapshot.dig("reference_design", "absolute_counts_transplanted") == false
tool_digest = sha256(TOOL_FILES.map { |relative| "#{relative}\0#{File.binread(File.join(ROOT, relative))}" }.join("\0"))
abort "Authority body tool digestがdriftしています" unless snapshot.fetch("tool_digest") == tool_digest

sources = YAML.safe_load(File.read(File.join(ROOT, "sources.lock.yaml")), aliases: false).fetch("sources").to_h { |source| [source.fetch("id"), source] }
records = snapshot.fetch("documents")
abort "Authority body document IDが重複しています" unless records.map { |record| record.fetch("id") }.uniq.length == records.length
actual_paths = Dir.glob(File.join(ROOT, "authority/body-inventory-draft/*.json")).sort
expected_paths = records.map { |record| File.join(ROOT, record.fetch("path")) }.sort
abort "Authority body artifact集合が一致しません" unless actual_paths == expected_paths

counts = Hash.new(0)
selector_counts = Hash.new(0)
anchor_ids = {}
represented_sources = {}
records.each do |record|
  exact_keys!(record, %w[id path digest fetch_status source_entries anchors anchors_by_selector], "Authority body index record")
  path = File.join(ROOT, record.fetch("path"))
  abort "Authority body artifact digestが不正です: #{record.fetch('id')}" unless "sha256:#{Digest::SHA256.file(path).hexdigest}" == record.fetch("digest")
  artifact = JSON.parse(File.read(path))
  reject_body_fields!(artifact, record.fetch("path"))
  exact_keys!(artifact, %w[document_id source_ids authority_url document_locator locked_source_digest locked_body_digest fetch schema_version extraction anchors], "Authority body artifact")
  exact_keys!(artifact.fetch("fetch"), %w[status fetched_digest locked_digest_match error_digest], "Authority body fetch")
  exact_keys!(artifact.fetch("extraction"), %w[method tool tool_digest selector_contract selector_exhaustive_for_locked_body authority_semantics_exhaustive review_status body_storage], "Authority body extraction")
  abort "Authority body artifact identityが不正です" unless artifact.fetch("document_id") == record.fetch("id")
  abort "Authority body review/storage境界が不正です" unless artifact.dig("extraction", "method") == "sgml-raw-anchor-selector-v1" && artifact.dig("extraction", "tool_digest") == tool_digest && artifact.dig("extraction", "selector_contract") == SELECTORS && artifact.dig("extraction", "authority_semantics_exhaustive") == false && artifact.dig("extraction", "review_status") == "automated-unreviewed" && artifact.dig("extraction", "body_storage") == "digest-locator-and-offset-only"
  artifact.fetch("source_ids").each do |source_id|
    source = sources.fetch(source_id)
    represented_sources[source_id] = true
    abort "Authority body Source Lock identityが不正です" unless artifact.fetch("locked_source_digest") == source.fetch("digest") && artifact.fetch("authority_url") == source.fetch("url")
  end
  status = artifact.dig("fetch", "status")
  counts[status] += 1
  matched = status == "matched"
  abort "Matched body境界が不正です" if matched && (artifact.dig("fetch", "locked_digest_match") != true || artifact.dig("fetch", "fetched_digest") != artifact.fetch("locked_body_digest") || artifact.dig("extraction", "selector_exhaustive_for_locked_body") != true || artifact.fetch("anchors").empty?)
  abort "Unmatched bodyにanchorを保持できません" if !matched && (!artifact.fetch("anchors").empty? || artifact.dig("extraction", "selector_exhaustive_for_locked_body") != false)
  local_selector_counts = Hash.new(0)
  artifact.fetch("anchors").each_with_index do |anchor, position|
    exact_keys!(anchor, %w[id locator locator_kind raw_selector element_name parent_anchor_id context_start context_end context_unit context_digest classification_status surface_ids behavior_ids], "Authority raw anchor")
    abort "Authority anchor IDが重複しています: #{anchor.fetch('id')}" if anchor_ids.key?(anchor.fetch("id"))
    anchor_ids[anchor.fetch("id")] = record.fetch("id")
    abort "Authority anchor digest/offsetが不正です" unless anchor.fetch("id").match?(/\Aanchor-pg-[a-f0-9]{20}\z/) && anchor.fetch("context_digest").match?(/\Asha256:[a-f0-9]{64}\z/) && anchor.fetch("context_start").is_a?(Integer) && anchor.fetch("context_end").is_a?(Integer) && anchor.fetch("context_end") > anchor.fetch("context_start") && anchor.fetch("context_unit") == "byte"
    abort "Authority anchorをHuman review前に昇格できません" unless anchor.fetch("classification_status") == "pending-human" && anchor.fetch("surface_ids") == [] && anchor.fetch("behavior_ids") == []
    if position.zero?
      abort "Authority document rootが不正です" unless anchor.fetch("raw_selector") == "document-root" && anchor.fetch("locator") == "document-root" && anchor.fetch("parent_anchor_id").nil?
    else
      abort "Authority raw fragmentが不正です" unless anchor.fetch("raw_selector") == "sgml-id-attribute" && anchor.fetch("locator").start_with?("#") && anchor.fetch("parent_anchor_id") == artifact.fetch("anchors").first.fetch("id")
    end
    local_selector_counts[anchor.fetch("raw_selector")] += 1
    selector_counts[anchor.fetch("raw_selector")] += 1
  end
  abort "Authority anchor index countが不正です" unless record.fetch("anchors") == artifact.fetch("anchors").length && record.fetch("anchors_by_selector") == local_selector_counts.sort.to_h && record.fetch("fetch_status") == status && record.fetch("source_entries") == artifact.fetch("source_ids").length

  next unless SOURCE_ROOT && matched
  commit, locator = artifact.fetch("document_locator").delete_prefix("git:").split(":", 2)
  abort "Authority source locator commitが不正です" unless commit == SOURCE_COMMIT
  bytes = File.binread(File.join(SOURCE_ROOT, locator))
  abort "Authority document digestがSource checkoutと一致しません" unless sha256(bytes) == artifact.fetch("locked_body_digest")
  artifact.fetch("anchors").each do |anchor|
    context = bytes.byteslice(anchor.fetch("context_start")...anchor.fetch("context_end"))
    abort "Authority anchor context digestがSource checkoutと一致しません" unless context && sha256(context) == anchor.fetch("context_digest")
  end
end

summary = snapshot.fetch("summary")
abort "Source entryをDocument母集団へ接続できていません" unless represented_sources.keys.sort == sources.keys.sort && summary.fetch("source_entries") == sources.length
abort "Authority body summaryが不正です" unless summary.fetch("unique_documents") == records.length && summary.fetch("matched_documents") == counts["matched"] && summary.fetch("stale_documents") == counts["stale"] && summary.fetch("failed_documents") == counts["failed"] && summary.fetch("selector_exhaustive_documents") == counts["matched"] && summary.fetch("raw_anchor_candidates") == anchor_ids.length && summary.fetch("anchors_by_selector") == selector_counts.sort.to_h
abort "Raw anchorをSemantic Surface/Depth達成へ算入できません" unless summary.fetch("pending_human_anchors") == anchor_ids.length && summary.fetch("human_reviewed_anchors") == 0 && summary.fetch("promoted_surface_artifacts") == 0 && summary.fetch("promoted_atomic_behaviors") == 0 && summary.fetch("authority_semantics_exhaustive") == false && summary.fetch("postgresql_authority_denominator_closed") == false

frontend = File.expand_path("../frontend-behavior-atlas", ROOT)
if File.directory?(File.join(frontend, ".git"))
  reference_files = {
    "scripts/lib/authority-body-inventory.ts"=>["04f62a0b63981c62a7ab90f39637c71745642e84a3bdd4404ce715a0163ebe76", 20_216],
    "scripts/lib/authority-body-baseline.ts"=>["0dc48dc9e62fdc9cd8493e9b5827b4cf5948c4b72df3374d5ebcc73ac344009c", 8_170]
  }
  reference_files.each do |relative, (digest, size)|
    body, _error, status = Open3.capture3("git", "-C", frontend, "show", "841ec2fa399606a10305021a8bcd396713b8cee5:#{relative}")
    abort "FE Authority body referenceが一致しません: #{relative}" unless status.success? && body.bytesize == size && Digest::SHA256.hexdigest(body) == digest
  end
end
puts "Verified Authority body inventory: documents=#{records.length} matched=#{counts['matched']} stale=#{counts['stale']} failed=#{counts['failed']} raw_anchors=#{anchor_ids.length} pending_human=#{anchor_ids.length} promoted=0"
