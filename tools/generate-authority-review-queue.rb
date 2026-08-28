#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require_relative "lib/authority-review-queue"

root = File.expand_path("..", __dir__)
index, batches, ledger = AuthorityReviewQueue.build(root)
directory = File.join(root, AuthorityReviewQueue::BATCH_DIR)
FileUtils.mkdir_p(directory)
expected = batches.map { |batch| "#{batch.fetch('batch_id')}.json" }.sort
Dir.glob(File.join(directory, "*.json")).each do |path|
  File.delete(path) unless expected.include?(File.basename(path))
end
batches.each do |batch|
  File.write(File.join(directory, "#{batch.fetch('batch_id')}.json"), JSON.pretty_generate(batch) + "\n")
end
FileUtils.mkdir_p(File.dirname(File.join(root, AuthorityReviewQueue::LEDGER_PATH)))
File.write(File.join(root, AuthorityReviewQueue::LEDGER_PATH), JSON.pretty_generate(ledger) + "\n")
File.write(File.join(root, AuthorityReviewQueue::INDEX_PATH), JSON.pretty_generate(index) + "\n")
puts "Authority review queue generated: anchors=#{index.dig('summary', 'queued_anchors')} batches=#{batches.length} pending=#{index.dig('summary', 'pending_human')} stale_holds=#{index.dig('summary', 'stale_document_holds')} unavailable_holds=#{index.dig('summary', 'unavailable_document_holds')} decisions=#{ledger.fetch('decisions').length}"
