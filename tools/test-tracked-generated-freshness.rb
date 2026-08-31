#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "lib/tracked_generated_freshness"

root = TrackedGeneratedFreshness::ROOT
failures = []

TrackedGeneratedFreshness.with_tempdir("pgra-generated-freshness-test.") do |tmp|
  left = File.join(tmp, "left")
  right = File.join(tmp, "right")
  FileUtils.mkdir_p(left)
  FileUtils.mkdir_p(right)
  TrackedGeneratedFreshness.copy_repo(root, left)
  TrackedGeneratedFreshness.copy_repo(root, right)
  commands = TrackedGeneratedFreshness.profile("scenario-proofs").fetch("commands")
  TrackedGeneratedFreshness.run_generators!(left, commands)
  TrackedGeneratedFreshness.run_generators!(right, commands)
  begin
    TrackedGeneratedFreshness.compare_roots!(left, right, "scenario-proofs")
  rescue RuntimeError => e
    failures << "scenario-proofs deterministic regeneration failed: #{e.message}"
  end
  proof = File.read(File.join(left, "evidence/scenarios/behaviors/concurrency.deadlock/boundary.proof.json"))
  failures << "benchmark_records empty array was not canonically serialized" unless proof.include?('"benchmark_records": []')
  failures << "compatibility_records empty array was not canonically serialized" unless proof.include?('"compatibility_records": []')
  failures << "legacy blank-line empty array serialization remained" if proof.include?("\"benchmark_records\": [\n\n") || proof.include?("\"compatibility_records\": [\n\n")
end

TrackedGeneratedFreshness.with_tempdir("pgra-generated-freshness-test.") do |tmp|
  clone = File.join(tmp, "clone")
  FileUtils.mkdir_p(clone)
  TrackedGeneratedFreshness.copy_repo(root, clone)
  target = File.join(clone, "evidence/scenarios/behaviors/concurrency.deadlock/boundary.proof.json")
  File.write(target, File.read(target).sub('"status": "pattern-specific-gap"', '"status": "tampered-gap"'))
  begin
    TrackedGeneratedFreshness.compare_roots!(root, clone)
    failures << "tampered generated output was accepted"
  rescue RuntimeError => e
    failures << "tampered output rejection message missing" unless e.message.include?("Generated output drift: evidence/scenarios/behaviors/concurrency.deadlock/boundary.proof.json")
  end
end

TrackedGeneratedFreshness.with_tempdir("pgra-generated-freshness-test.") do |tmp|
  clone = File.join(tmp, "clone")
  FileUtils.mkdir_p(clone)
  TrackedGeneratedFreshness.copy_repo(root, clone)
  missing = File.join(clone, "evidence/scenarios/behaviors/concurrency.deadlock/boundary.proof.json")
  FileUtils.rm_f(missing)
  begin
    TrackedGeneratedFreshness.compare_roots!(root, clone)
    failures << "missing generated output was accepted"
  rescue RuntimeError => e
    failures << "missing output rejection message missing" unless e.message.include?("Generated output set drift: missing evidence/scenarios/behaviors/concurrency.deadlock/boundary.proof.json")
  end
end

TrackedGeneratedFreshness.with_tempdir("pgra-generated-freshness-test.") do |tmp|
  clone = File.join(tmp, "clone")
  FileUtils.mkdir_p(clone)
  TrackedGeneratedFreshness.copy_repo(root, clone)
  extra = File.join(clone, "evidence/scenarios/behaviors/concurrency.deadlock/unexpected.proof.json")
  File.write(extra, "{}\n")
  begin
    TrackedGeneratedFreshness.compare_roots!(root, clone)
    failures << "unexpected generated output was accepted"
  rescue RuntimeError => e
    failures << "unexpected output rejection message missing" unless e.message.include?("Generated output set drift: unexpected evidence/scenarios/behaviors/concurrency.deadlock/unexpected.proof.json")
  end
end

abort failures.join("\n") unless failures.empty?
puts "Tracked generated freshnessを検証しました: scenario-proofs 2 clean roots byte-identical; negative fixtures 3/3 rejected"
