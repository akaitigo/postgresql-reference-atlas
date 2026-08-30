#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "tmpdir"

root = File.expand_path("..", __dir__)
makefile = File.join(root, "Makefile")
expected = [
  "ledger-output-verify",
  "evidence-dependency-verify",
  "tracked-generated-freshness"
].freeze
target_header = "evidence-pipeline-clean:\n"

verify_target = lambda do |makefile_path|
  output, status = Open3.capture2e("make", "-n", "-f", makefile_path, "evidence-pipeline-clean", chdir: root)
  raise "evidence-pipeline-clean command baseline failed" unless status.success?

  positions = expected.map do |command|
    pattern = /^.*make #{Regexp.escape(command)}$/
    match = output.to_enum(:scan, pattern).map { Regexp.last_match.begin(0) }.first
    raise "evidence-pipeline-clean missing command: #{command}" unless match

    match
  end
  raise "evidence-pipeline-clean command order drifted" unless positions == positions.sort
  raise "evidence-pipeline-clean no-op detected" if output.include?("@echo noop")
end

verify_target.call(makefile)

expected.each do |command|
  Dir.mktmpdir("pgra-evidence-pipeline-clean.", "/private/tmp") do |tmp|
    fixture = File.join(tmp, "Makefile")
    lines = File.readlines(makefile)
    target_index = lines.index(target_header)
    raise "evidence-pipeline-clean target not found" unless target_index

    command_index = expected.index(command)
    lines[target_index + 1 + command_index] = "\t@echo noop\n"
    File.write(fixture, lines.join)
    begin
      verify_target.call(fixture)
      abort "no-op fixture was accepted for #{command}"
    rescue RuntimeError => e
      next if e.message.include?(command) || e.message.include?("no-op detected")

      abort e.message
    end
  end
end

puts "evidence-pipeline-clean command baselineを検証しました: #{expected.length}/#{expected.length} commands, no-op fixtures rejected"
