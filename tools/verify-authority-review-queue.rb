#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/authority-review-queue"
require "stringio"

root = File.expand_path("..", __dir__)
expected_index, expected_batches, ledger = AuthorityReviewQueue.build(root)
index = JSON.parse(File.read(File.join(root, AuthorityReviewQueue::INDEX_PATH)))
AuthorityReviewQueue.reject_body_fields!(index)
abort "Authority review queue indexが決定論生成値と一致しません" unless index == expected_index

expected_files = expected_batches.map { |batch| "#{batch.fetch('batch_id')}.json" }.sort
actual_files = Dir.glob(File.join(root, AuthorityReviewQueue::BATCH_DIR, "*.json")).map { |path| File.basename(path) }.sort
abort "Authority review batch file集合が不正です" unless actual_files == expected_files
queued_ids = []
expected_batches.each do |batch|
  path = File.join(root, AuthorityReviewQueue::BATCH_DIR, "#{batch.fetch('batch_id')}.json")
  actual = JSON.parse(File.read(path))
  AuthorityReviewQueue.reject_body_fields!(actual, path)
  abort "Authority review batchが決定論生成値と一致しません: #{batch.fetch('batch_id')}" unless actual == batch
  record = index.fetch("batches").find { |item| item.fetch("id") == batch.fetch("batch_id") }
  abort "Authority review batch digestが不正です" unless record && record.fetch("digest") == "sha256:#{Digest::SHA256.file(path).hexdigest}"
  queued_ids.concat(actual.fetch("items").map { |item| item.fetch("anchor_id") })
end

body_ids = JSON.parse(File.read(File.join(root, "authority/body-inventory.snapshot.json"))).fetch("documents").flat_map do |record|
  JSON.parse(File.read(File.join(root, record.fetch("path")))).fetch("anchors").map { |anchor| anchor.fetch("id") }
end
abort "Raw anchorがReview queueへ完全接続されていません" unless queued_ids.sort == body_ids.sort && queued_ids.uniq.length == queued_ids.length
summary = index.fetch("summary")
abort "Review queueをDepth達成へ算入できません" unless summary.fetch("queue_counts_as_depth_achievement") == false && summary.fetch("authority_semantics_exhaustive") == false
abort "全件pending-humanから開始していません" unless ledger.fetch("decisions") == [] && summary.fetch("pending_human") == queued_ids.length && summary.fetch("human_reviewed") == 0
abort "Priority/cluster/batchは提案に限定されます" unless index.fetch("machine_assistance") == "dedupe-candidate-cluster-priority-and-batch-only" && index.fetch("semantic_decisions") == "human-only"
abort "Stale documentをQueueへ投入できません" unless index.fetch("stale_holds").length == summary.fetch("stale_document_holds")

first_item = expected_batches.first.fetch("items").first
binding_keys = %w[anchor_id document_id authority_url document_locator locked_source_digest inventory_tool_digest review_queue_tool_digest locator context_start context_end context_unit context_digest]
binding = binding_keys.to_h { |key| [key, first_item.fetch(key)] }
valid_decision = {
  "decision_id"=>"decision.contract-test.include", "action"=>"include",
  "anchor_ids"=>[first_item.fetch("anchor_id")], "source_bindings"=>[binding],
  "rationale"=>"固定commitの一次資料locatorとcontext digestを人が照合し、独立したSurfaceとして扱う判断を記録するcontract testである。",
  "reviewer"=>"human-reviewer", "reviewed_at"=>"2026-08-28T12:00:00+09:00", "review_method"=>"manual-primary-source",
  "mapping"=>[{"old_anchor_id"=>first_item.fetch("anchor_id"), "new_item_ids"=>["surface.contract-test"]}],
  "result_items"=>[{"id"=>"surface.contract-test", "item_type"=>"surface"}]
}
valid_ledger = ledger.merge("decisions"=>[valid_decision])
AuthorityReviewQueue.validate_ledger!(valid_ledger, [first_item], index.fetch("queue_id"))
def rejected?
  original = $stderr
  $stderr = StringIO.new
  yield
  false
rescue SystemExit
  true
ensure
  $stderr = original
end
abort "Automated reviewerを拒否できません" unless rejected? { AuthorityReviewQueue.validate_ledger!(valid_ledger.merge("decisions"=>[valid_decision.merge("reviewer"=>"automated-bot")]), [first_item], index.fetch("queue_id")) }
abort "Mapping/result不一致を拒否できません" unless rejected? { AuthorityReviewQueue.validate_ledger!(valid_ledger.merge("decisions"=>[valid_decision.merge("result_items"=>[])]), [first_item], index.fetch("queue_id")) }

puts "Verified Authority review queue: anchors=#{queued_ids.length} batches=#{expected_batches.length} clusters=#{summary.fetch('candidate_clusters')} pending=#{summary.fetch('pending_human')} stale_holds=#{summary.fetch('stale_document_holds')} unavailable_holds=#{summary.fetch('unavailable_document_holds')} human_decisions=#{ledger.fetch('decisions').length} contract_negative_cases=2"
