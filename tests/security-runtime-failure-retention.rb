#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"

root = File.expand_path("..", __dir__)
report_path = File.join(root, "artifacts/pattern-scenarios/results.json")
report = JSON.parse(File.read(report_path))
artifacts = [report_path] + report.fetch("tests").flat_map do |test|
  [
    File.join(root, test.dig("trace", "path")),
    File.join(root, test.dig("screenshot", "path"))
  ]
end
failure_diagnostics = Dir.glob(File.join(root, "artifacts/pattern-scenario-failures/*.json")).sort
failure_records = failure_diagnostics.map { |path| JSON.parse(File.read(path)) }

abort "canonical scenario runtime report drifted" unless report.fetch("status") == "passed" && report.dig("counts", "rows") == 20 && report.dig("counts", "passed") == 20
abort "canonical security runtime attempts drifted" unless report.fetch("tests").all? { |test| test.fetch("attempts") == 1 && test.fetch("final_status") == "passed" }
abort "canonical security artifact retention drifted" unless artifacts.length == 41 && artifacts.uniq.length == 41 && artifacts.all? { |path| File.file?(path) }
abort "append-only failure diagnostics drifted" unless failure_diagnostics.map { |path| File.basename(path) } == [
  "security-001-20260830T214437Z-8458__closure.unknown.security.json",
  "security-001-20260830T220147Z-6908__closure.definitive-domain.performance.index.security.json"
] && failure_records.all? { |record| record.fetch("command") == "ruby tools/run-scenario-security-001.rb" }
abort "staging cleanup drifted" if Dir.exist?(File.join(root, "artifacts/.pattern-scenarios-next")) || Dir.exist?(File.join(root, "artifacts/.pattern-scenarios-prev"))

summary = {
  "attempt_policy"=>{"workers"=>1, "retries"=>0, "first_attempt_only"=>true},
  "staging_cleanup"=>{"pattern_scenarios_next_present"=>false, "pattern_scenarios_prev_present"=>false},
  "canonical_results"=>{"digest"=>"sha256:#{Digest::SHA256.file(report_path).hexdigest}", "rows"=>report.dig("counts", "rows"), "passed"=>report.dig("counts", "passed")},
  "retained_artifact_count"=>artifacts.length,
  "retained_failure_diagnostics"=>failure_diagnostics.zip(failure_records).map do |path, record|
    {
      "path"=>path.delete_prefix("#{root}/"),
      "digest"=>"sha256:#{Digest::SHA256.file(path).hexdigest}",
      "failed_row"=>record.fetch("failed_row"),
      "target"=>record.fetch("target"),
      "oracle_error"=>record.fetch("oracle_error")
    }
  end
}

puts JSON.pretty_generate(summary)
