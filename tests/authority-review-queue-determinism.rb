#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
GENERATED_PATHS = [
  "authority/review-queue.snapshot.json",
  "authority/reviews/decisions.json"
].freeze

def prepare_checkout(path, reverse: false)
  paths = %w[
    tools/lib/canonical-json.rb
    tools/lib/authority-review-queue.rb
    tools/generate-authority-review-queue.rb
    tools/verify-authority-review-queue.rb
  ]
  paths.reverse! if reverse
  paths.each do |relative|
    destination = File.join(path, relative)
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(File.join(ROOT, relative), destination)
  end
  FileUtils.mkdir_p(File.join(path, "authority/reviews"))
  FileUtils.cp(File.join(ROOT, "authority/reviews/decisions.json"), File.join(path, "authority/reviews/decisions.json"))
  %w[body-inventory.snapshot.json body-inventory-draft locator-draft].each do |relative|
    FileUtils.ln_s(File.join(ROOT, "authority", relative), File.join(path, "authority", relative))
  end
end

def run_tool(checkout, relative, locale)
  output, status = Open3.capture2e(
    {"LANG"=>locale, "LC_ALL"=>locale, "TZ"=>locale == "C" ? "UTC" : "Asia/Tokyo"},
    RbConfig.ruby, relative, chdir: checkout
  )
  abort "#{relative} failed in isolated checkout: #{output}" unless status.success?
end

def snapshot(checkout)
  paths = GENERATED_PATHS + Dir.glob(File.join(checkout, "authority/review-queue-draft/*.json"))
    .map { |path| path.delete_prefix("#{checkout}/") }.sort
  paths.to_h do |relative|
    body = File.binread(File.join(checkout, relative))
    [relative, "sha256:#{Digest::SHA256.hexdigest(body)}:#{body.bytesize}"]
  end
end

def repository_snapshot
  snapshot(ROOT)
end

def rejected?(checkout)
  _output, status = Open3.capture2e(RbConfig.ruby, "tools/verify-authority-review-queue.rb", chdir: checkout)
  !status.success?
end

Dir.mktmpdir("pg-authority-review-determinism-") do |temporary_root|
  first = File.join(temporary_root, "checkout-a")
  second = File.join(temporary_root, "different-path-checkout-b")
  [first, second].each { |path| FileUtils.mkdir_p(path) }
  prepare_checkout(first, reverse: false)
  prepare_checkout(second, reverse: true)

  run_tool(first, "tools/generate-authority-review-queue.rb", "C")
  run_tool(second, "tools/generate-authority-review-queue.rb", "ja_JP.UTF-8")
  first_snapshot = snapshot(first)
  second_snapshot = snapshot(second)
  abort "Authority review queueがcheckout path/locale/creation orderに依存しています" unless first_snapshot == second_snapshot
  abort "Authority review queue再生成がRepository固定byteと一致しません" unless first_snapshot == repository_snapshot

  batch = Dir.glob(File.join(first, "authority/review-queue-draft/*.json")).sort.first
  original = File.binread(batch)
  File.write(batch, original.sub('"pending-human"', '"tampered"'))
  abort "Authority review batch改ざんを拒否できません" unless rejected?(first)
  File.binwrite(batch, original)
  File.delete(batch)
  abort "Authority review batch縮小を拒否できません" unless rejected?(first)
end

puts "Verified Authority review queue determinism: two isolated checkouts byte-identical; tamper/shrink 2/2 rejected"
