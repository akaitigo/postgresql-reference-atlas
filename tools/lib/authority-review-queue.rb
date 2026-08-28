# frozen_string_literal: true

require "digest"
require "json"
require "time"

module AuthorityReviewQueue
  GENERATED_AT = "2026-08-28T00:00:00+09:00"
  INDEX_PATH = "authority/review-queue.snapshot.json"
  BATCH_DIR = "authority/review-queue-draft"
  LEDGER_PATH = "authority/reviews/decisions.json"
  TOOL_FILES = %w[
    tools/lib/authority-review-queue.rb
    tools/generate-authority-review-queue.rb
    tools/verify-authority-review-queue.rb
  ].freeze
  FORBIDDEN_FIELDS = %w[body text content excerpt quote snippet html markdown raw payload].freeze

  module_function

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

  def tool_digest(root)
    sha256(TOOL_FILES.map { |relative| "#{relative}\0#{File.binread(File.join(root, relative))}" }.join("\0"))
  end

  def short_hash(value, length = 16)
    Digest::SHA256.hexdigest(value)[0, length]
  end

  def artifact_digest(value)
    sha256(JSON.pretty_generate(value) + "\n")
  end

  def candidate_edges(root)
    edges = Hash.new { |hash, key| hash[key] = [] }
    Dir.glob(File.join(root, "authority/locator-draft/*.json")).sort.each do |path|
      artifact = JSON.parse(File.read(path))
      artifact.fetch("candidate_surfaces").each do |candidate|
        edges[candidate.fetch("locator")] << candidate.fetch("authority_surface_id")
      end
    end
    edges.transform_values { |values| values.uniq.sort }
  end

  def priority_for(anchor, edge_ids)
    return [0, ["existing-generated-mapping-locator-match"]] if edge_ids.any?
    return [1, ["fixed-sgml-id-anchor"]] if anchor.fetch("raw_selector") == "sgml-id-attribute"

    [2, ["document-structure-anchor"]]
  end

  def batch_id(priority, selector, anchor_id)
    bucket = (short_hash(anchor_id, 2).to_i(16) % 64).to_s(16).rjust(2, "0")
    "review-p#{priority}-#{selector}-#{bucket}"
  end

  def empty_ledger(queue_id)
    {"schema_version"=>1, "atlas_id"=>"postgresql-reference-atlas", "queue_id"=>queue_id,
     "status"=>"incomplete-human-review-required", "decisions"=>[]}
  end

  def build(root)
    body_index = JSON.parse(File.read(File.join(root, "authority/body-inventory.snapshot.json")))
    queue_tool_digest = tool_digest(root)
    artifacts = body_index.fetch("documents").map do |record|
      JSON.parse(File.read(File.join(root, record.fetch("path"))))
    end
    all_anchor_ids = artifacts.flat_map { |artifact| artifact.fetch("anchors").map { |anchor| anchor.fetch("id") } }.sort
    queue_id = "authority-review-pg-#{short_hash("#{body_index.fetch('input_digest')}\0#{all_anchor_ids.join("\0")}", 20)}"
    input_digest = sha256(JSON.generate({"body_input_digest"=>body_index.fetch("input_digest"), "anchor_ids"=>all_anchor_ids}))
    edges = candidate_edges(root)

    cluster_groups = Hash.new { |hash, key| hash[key] = [] }
    artifacts.each do |artifact|
      artifact.fetch("anchors").each do |anchor|
        next unless anchor.fetch("raw_selector") == "sgml-id-attribute"

        cluster_groups[[anchor.fetch("element_name"), anchor.fetch("locator")]] << anchor.fetch("id")
      end
    end
    cluster_by_anchor = {}
    cluster_groups.each do |key, ids|
      next unless ids.length > 1

      cluster_id = "candidate-cluster-pg-#{short_hash(key.join("\0"), 20)}"
      ids.each { |id| cluster_by_anchor[id] = cluster_id }
    end

    grouped = Hash.new { |hash, key| hash[key] = [] }
    artifacts.select { |artifact| artifact.dig("fetch", "status") == "matched" }.each do |artifact|
      document_path = artifact.fetch("document_locator").start_with?("git:") ? artifact.fetch("document_locator").split(":", 3).fetch(2) : artifact.fetch("document_locator")
      artifact.fetch("anchors").each do |anchor|
        locator_key = anchor.fetch("locator") == "document-root" ? document_path : "#{document_path}#{anchor.fetch('locator')}"
        edge_ids = edges.fetch(locator_key, [])
        priority, reasons = priority_for(anchor, edge_ids)
        id = batch_id(priority, anchor.fetch("raw_selector"), anchor.fetch("id"))
        grouped[id] << {
          "anchor_id"=>anchor.fetch("id"), "document_id"=>artifact.fetch("document_id"),
          "authority_url"=>artifact.fetch("authority_url"), "document_locator"=>artifact.fetch("document_locator"),
          "source_ids"=>artifact.fetch("source_ids"), "locked_source_digest"=>artifact.fetch("locked_body_digest"),
          "inventory_tool_digest"=>artifact.dig("extraction", "tool_digest"), "review_queue_tool_digest"=>queue_tool_digest,
          "locator"=>anchor.fetch("locator"), "locator_kind"=>anchor.fetch("locator_kind"),
          "raw_selector"=>anchor.fetch("raw_selector"), "element_name"=>anchor.fetch("element_name"),
          "parent_anchor_id"=>anchor.fetch("parent_anchor_id"), "context_start"=>anchor.fetch("context_start"),
          "context_end"=>anchor.fetch("context_end"), "context_unit"=>anchor.fetch("context_unit"),
          "context_digest"=>anchor.fetch("context_digest"), "existing_mapping_candidate_ids"=>edge_ids,
          "priority"=>priority, "priority_reasons"=>reasons,
          "candidate_cluster_id"=>cluster_by_anchor[anchor.fetch("id")], "batch_id"=>id,
          "state"=>"pending-human"
        }
      end
    end

    batches = grouped.sort.map do |id, items|
      {"schema_version"=>1, "queue_id"=>queue_id, "batch_id"=>id, "status"=>"pending-human",
       "machine_assistance"=>"ordering-and-candidate-clustering-only", "semantic_decisions"=>"none",
       "items"=>items.sort_by { |item| item.fetch("anchor_id") }}
    end
    records = batches.map do |batch|
      parts = batch.fetch("batch_id").split("-")
      {"id"=>batch.fetch("batch_id"), "path"=>"#{BATCH_DIR}/#{batch.fetch('batch_id')}.json",
       "digest"=>artifact_digest(batch), "priority"=>parts.fetch(1).delete_prefix("p").to_i,
       "raw_selector"=>parts[2...-1].join("-"), "bucket"=>parts.last, "items"=>batch.fetch("items").length}
    end
    items = batches.flat_map { |batch| batch.fetch("items") }
    priority_counts = (0..2).to_h { |priority| [priority.to_s, items.count { |item| item.fetch("priority") == priority }] }
    stale_holds = artifacts.select { |artifact| artifact.dig("fetch", "status") == "stale" }.map do |artifact|
      {"document_id"=>artifact.fetch("document_id"), "authority_url"=>artifact.fetch("authority_url"),
       "document_locator"=>artifact.fetch("document_locator"), "source_ids"=>artifact.fetch("source_ids"),
       "locked_source_digest"=>artifact.fetch("locked_body_digest"), "inventory_tool_digest"=>artifact.dig("extraction", "tool_digest"),
       "review_queue_tool_digest"=>queue_tool_digest, "fetched_digest"=>artifact.dig("fetch", "fetched_digest"),
       "status"=>"hold-stale-document-relock-required", "reason"=>"locked-document-body-digest-mismatch"}
    end.sort_by { |hold| hold.fetch("document_id") }
    unavailable_holds = artifacts.select { |artifact| artifact.dig("fetch", "status") == "failed" }.map do |artifact|
      {"document_id"=>artifact.fetch("document_id"), "authority_url"=>artifact.fetch("authority_url"),
       "document_locator"=>artifact.fetch("document_locator"), "source_ids"=>artifact.fetch("source_ids"),
       "locked_source_digest"=>artifact.fetch("locked_body_digest"), "inventory_tool_digest"=>artifact.dig("extraction", "tool_digest"),
       "review_queue_tool_digest"=>queue_tool_digest, "error_digest"=>artifact.dig("fetch", "error_digest"),
       "status"=>"hold-unavailable-document-retrieval-required", "reason"=>"locked-document-body-unavailable"}
    end.sort_by { |hold| hold.fetch("document_id") }

    ledger_path = File.join(root, LEDGER_PATH)
    ledger = File.file?(ledger_path) ? JSON.parse(File.read(ledger_path)) : empty_ledger(queue_id)
    validate_ledger!(ledger, items, queue_id)
    reviewed = ledger.fetch("decisions").flat_map { |decision| decision.fetch("anchor_ids") }.uniq.length
    actions = %w[include exclude merge split].to_h { |action| [action, ledger.fetch("decisions").count { |decision| decision.fetch("action") == action }] }
    index = {
      "schema_version"=>1, "atlas_id"=>"postgresql-reference-atlas", "generated_at"=>GENERATED_AT,
      "status"=>"incomplete-human-review-required", "queue_id"=>queue_id, "input_digest"=>input_digest,
      "tool_digest"=>queue_tool_digest, "decision_ledger"=>LEDGER_PATH,
      "body_storage"=>"digest-locator-and-offset-only",
      "machine_assistance"=>"dedupe-candidate-cluster-priority-and-batch-only", "semantic_decisions"=>"human-only",
      "summary"=>{"eligible_documents"=>artifacts.count { |artifact| artifact.dig("fetch", "status") == "matched" },
                    "queued_anchors"=>items.length, "pending_human"=>items.length-reviewed, "human_reviewed"=>reviewed,
                    "priority_counts"=>priority_counts, "candidate_clusters"=>cluster_by_anchor.values.uniq.length,
                    "clustered_anchors"=>cluster_by_anchor.length, "batches"=>batches.length,
                    "stale_document_holds"=>stale_holds.length, "unavailable_document_holds"=>unavailable_holds.length,
                    "decisions"=>ledger.fetch("decisions").length, "included"=>actions.fetch("include"),
                    "excluded"=>actions.fetch("exclude"), "merged"=>actions.fetch("merge"), "split"=>actions.fetch("split"),
                    "authority_semantics_exhaustive"=>false, "queue_counts_as_depth_achievement"=>false},
      "batches"=>records, "stale_holds"=>stale_holds, "unavailable_holds"=>unavailable_holds
    }
    [index, batches, ledger]
  end

  def validate_ledger!(ledger, items, queue_id)
    exact_keys!(ledger, %w[schema_version atlas_id queue_id status decisions], "Authority review decision ledger")
    abort "Authority review ledger identityが不正です" unless ledger.fetch("schema_version") == 1 && ledger.fetch("atlas_id") == "postgresql-reference-atlas" && ledger.fetch("queue_id") == queue_id && ledger.fetch("status") == "incomplete-human-review-required"
    item_by_id = items.to_h { |item| [item.fetch("anchor_id"), item] }
    seen_anchors = {}
    seen_decisions = {}
    new_item_owner = {}
    ledger.fetch("decisions").each do |decision|
      exact_keys!(decision, %w[decision_id action anchor_ids source_bindings rationale reviewer reviewed_at review_method mapping result_items], "Authority review decision")
      id = decision.fetch("decision_id")
      abort "Authority review decision ID/actionが不正です: #{id}" unless id.match?(/\Adecision\.[a-z0-9.-]+\z/) && %w[include exclude merge split].include?(decision.fetch("action")) && !seen_decisions[id]
      seen_decisions[id] = true
      reviewer = decision.fetch("reviewer").strip
      abort "人手review provenanceが不足しています: #{id}" unless decision.fetch("review_method") == "manual-primary-source" && decision.fetch("rationale").strip.length >= 40 && reviewer.length >= 2 && !reviewer.match?(/\A(?:auto(?:mated)?|agent|bot|system|machine)(?:$|[-_. ])/i)
      begin
        Time.iso8601(decision.fetch("reviewed_at"))
      rescue ArgumentError
        abort "reviewed_atがISO date-timeではありません: #{id}"
      end
      anchor_ids = decision.fetch("anchor_ids")
      abort "Decision anchor/binding/mapping cardinalityが不正です: #{id}" if anchor_ids.empty? || anchor_ids.uniq.length != anchor_ids.length || decision.fetch("source_bindings").length != anchor_ids.length || decision.fetch("mapping").length != anchor_ids.length
      binding_by_id = decision.fetch("source_bindings").to_h { |binding| [binding.fetch("anchor_id"), binding] }
      mapping_by_id = decision.fetch("mapping").to_h { |mapping| [mapping.fetch("old_anchor_id"), mapping] }
      abort "Decision binding/mapping IDが重複しています: #{id}" unless binding_by_id.length == anchor_ids.length && mapping_by_id.length == anchor_ids.length
      anchor_ids.each do |anchor_id|
        abort "Queue外または複数decisionのanchorです: #{anchor_id}" unless item_by_id[anchor_id] && !seen_anchors[anchor_id]
        seen_anchors[anchor_id] = true
        item = item_by_id.fetch(anchor_id)
        binding = binding_by_id.fetch(anchor_id)
        binding_keys = %w[anchor_id document_id authority_url document_locator locked_source_digest inventory_tool_digest review_queue_tool_digest locator context_start context_end context_unit context_digest]
        exact_keys!(binding, binding_keys, "Authority review source binding")
        expected = binding_keys.to_h { |key| [key, item.fetch(key)] }
        abort "Decision source/tool/locator bindingがQueueと一致しません: #{anchor_id}" unless binding == expected
        mapping = mapping_by_id.fetch(anchor_id)
        exact_keys!(mapping, %w[old_anchor_id new_item_ids], "Authority review mapping")
        abort "Decision mapping IDが不正です: #{anchor_id}" unless mapping.fetch("new_item_ids").uniq.length == mapping.fetch("new_item_ids").length && mapping.fetch("new_item_ids").all? { |new_id| new_id.match?(/\A[a-z][a-z0-9.-]+\z/) }
      end
      decision.fetch("result_items").each do |result|
        exact_keys!(result, %w[id item_type], "Authority review result")
        abort "Decision resultが不正です: #{id}" unless result.fetch("id").match?(/\A[a-z][a-z0-9.-]+\z/) && %w[surface atomic-behavior].include?(result.fetch("item_type"))
      end
      mapped_ids = decision.fetch("mapping").flat_map { |mapping| mapping.fetch("new_item_ids") }.uniq.sort
      result_ids = decision.fetch("result_items").map { |result| result.fetch("id") }.uniq.sort
      abort "Decision mappingとresultが一致しません: #{id}" unless mapped_ids == result_ids && result_ids.length == decision.fetch("result_items").length
      action = decision.fetch("action")
      abort "exclude mappingが不正です: #{id}" if action == "exclude" && mapped_ids.any?
      abort "include mappingが不正です: #{id}" if action == "include" && decision.fetch("mapping").any? { |mapping| mapping.fetch("new_item_ids").empty? }
      abort "includeでnew itemを共有する場合はmergeが必要です: #{id}" if action == "include" && mapped_ids.length != decision.fetch("mapping").sum { |mapping| mapping.fetch("new_item_ids").length }
      result_sets = decision.fetch("mapping").map { |mapping| mapping.fetch("new_item_ids").sort }
      abort "merge mappingが不正です: #{id}" if action == "merge" && (anchor_ids.length < 2 || result_sets.any?(&:empty?) || result_sets.uniq.length != 1)
      abort "split mappingが不正です: #{id}" if action == "split" && (anchor_ids.length != 1 || result_sets.first.length < 2)
      mapped_ids.each do |new_id|
        abort "new item IDが複数decisionで共有されています: #{new_id}" if new_item_owner[new_id] && new_item_owner[new_id] != id
        new_item_owner[new_id] = id
      end
    end
    seen_anchors.keys
  end
end
