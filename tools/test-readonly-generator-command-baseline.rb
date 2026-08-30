#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "tmpdir"

require_relative "lib/tracked_generated_freshness"

root = File.expand_path("..", __dir__)
makefile = File.join(root, "Makefile")
env = {"READ_ONLY_TRACKED_GENERATORS"=>"1"}
targets = {
  "test-static"=>"ruby tools/verify-generated-output-readonly.rb static-gates",
  "eval"=>"ruby tools/verify-generated-output-readonly.rb eval",
  "scenario-proofs-generate"=>"ruby tools/verify-generated-output-readonly.rb scenario-proofs",
  "scenario-closure-plan-generate"=>"ruby tools/verify-generated-output-readonly.rb scenario-closure-plan",
  "provenance"=>"ruby tools/verify-generated-output-readonly.rb provenance",
  "evidence-dependency-generate"=>"ruby tools/verify-generated-output-readonly.rb graph"
}.freeze

static_profile = TrackedGeneratedFreshness.profile("static-gates")
abort "static-gates read-only verifier must execute scripts/static-gates.sh inside the temporary copy" unless static_profile.fetch("commands") == [["bash", "scripts/static-gates.sh"]]

verify_targets = lambda do |makefile_path|
  targets.each do |target, expected|
    output, status = Open3.capture2e(env, "make", "-n", "-f", makefile_path, target, chdir: root)
    raise "read-only command baseline failed for #{target}" unless status.success?
    raise "read-only command drift for #{target}" unless output.include?(expected)
    raise "read-only no-op detected for #{target}" if output.include?("read-only tracked generator freshness already verified")
  end
end

verify_targets.call(makefile)
targets.each do |target, expected|
  Dir.mktmpdir("pgra-command-baseline.", "/private/tmp") do |tmp|
    fixture = File.join(tmp, "Makefile")
    content = File.read(makefile)
    File.write(fixture, content.sub(expected, "@echo noop"))
    begin
      verify_targets.call(fixture)
      abort "no-op fixture was accepted for #{target}"
    rescue RuntimeError => e
      next if e.message.include?(target)

      abort e.message
    end
  end
end

puts "Read-only generator command baselineを検証しました: #{targets.length}/#{targets.length} targets, no-op fixtures rejected"
