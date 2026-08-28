#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "yaml"

root = File.expand_path("..", __dir__)
stale = []
checked = 0
Dir.glob(File.join(root, "evidence", "*.evidence.yaml")).sort.each do |path|
  evidence = YAML.safe_load(File.read(path), aliases: false)
  id = evidence.fetch("id")
  harness_relative = evidence["harness_path"]
  unless harness_relative
    stale << "#{id}: harness_pathがありません"
    next
  end
  harness = File.join(root, harness_relative)
  unless File.file?(harness)
    stale << "#{id}: #{harness_relative}がありません"
    next
  end
  expected = "sha256:#{Digest::SHA256.file(harness).hexdigest}"
  stale << "#{id}: Harness Manifest Digestが一致しません" unless evidence.fetch("harness_digest") == expected
  File.foreach(harness, chomp: true) do |line|
    digest, relative = line.split(/  /, 2)
    source = relative && File.join(root, relative)
    if !digest&.match?(/\A[a-f0-9]{64}\z/) || !source || !File.file?(source)
      stale << "#{id}: 不正なHarness entry #{line.inspect}"
    elsif Digest::SHA256.file(source).hexdigest != digest
      stale << "#{id}: #{relative}がEvidence生成後に変更されています"
    end
  end
  checked += 1
end

unless stale.empty?
  warn "Harness Digestが失効したEvidenceがあります（#{stale.length}/#{checked}）"
  warn stale.map { |entry| "- #{entry}" }.join("\n")
  exit 1
end

puts "Evidence Harness Manifestを確認しました: #{checked}/#{checked}"
