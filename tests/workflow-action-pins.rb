#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)
WORKFLOW_PATH = File.join(ROOT, ".github/workflows/ci.yml")
PIN = "actions/checkout@11d5960a326750d5838078e36cf38b85af677262"

def verify!(path)
  workflow = YAML.safe_load(File.read(path), aliases: false)
  steps = workflow.fetch("jobs").values.flat_map { |job| Array(job["steps"]) }
  checkout_uses = steps.map { |step| step["uses"] if step["uses"].to_s.start_with?("actions/checkout@") }.compact

  raise "actions/checkout steps must remain exactly 3, got #{checkout_uses.length}" unless checkout_uses.length == 3
  invalid = checkout_uses.reject { |entry| entry == PIN }
  raise "actions/checkout pin drift detected: #{invalid.first}" unless invalid.empty?
end

verify!(WORKFLOW_PATH)

Dir.mktmpdir("pgra-workflow-pins.") do |tmp|
  fixture = File.join(tmp, "ci.yml")
  File.write(fixture, File.read(WORKFLOW_PATH).sub(PIN, "actions/checkout@v4"))
  begin
    verify!(fixture)
    abort "mutable actions/checkout tag regression was accepted"
  rescue RuntimeError => e
    abort e.message unless e.message.include?("pin drift detected")
  end
end

puts "Workflow action pin contractを検証しました: actions/checkout pinned=3/3, mutable tag regression rejected"
