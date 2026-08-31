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
required_failure_diagnostics = [
  "security-001-20260830T214437Z-8458__closure.unknown.security.json",
  "security-001-20260830T220147Z-6908__closure.definitive-domain.performance.index.security.json",
  "security-001-20260831T051312Z-88696__closure.definitive-domain.performance.statistics.security.json",
  "security-001-20260831T051608Z-89784__closure.definitive-domain.query.extension.security.json",
  "security-001-20260831T124834Z-64071__closure.unknown.security.json",
  "security-001-20260831T130842Z-11923__closure.unknown.security.json",
  "security-001-20260831T133706Z-5245__closure.definitive-domain.query.security.security.json",
  "security-001-20260831T134549Z-18426__closure.definitive-domain.query.security.security.json",
  "security-001-20260831T135816Z-90092__closure.unknown.security.json",
  "security-001-20260831T141554Z-15021__closure.definitive-domain.query.sql-surface.security.json",
  "security-001-20260831T143713Z-11603__closure.definitive-domain.query.sql-surface.security.json"
]

abort "canonical scenario runtime report drifted" unless report.fetch("status") == "passed" && report.dig("counts", "rows") == 28 && report.dig("counts", "passed") == 28
abort "canonical security runtime attempts drifted" unless report.fetch("tests").all? { |test| test.fetch("attempts") == 1 && test.fetch("final_status") == "passed" }
abort "canonical security artifact retention drifted" unless artifacts.length == 57 && artifacts.uniq.length == 57 && artifacts.all? { |path| File.file?(path) }
actual_failure_names = failure_diagnostics.map { |path| File.basename(path) }
abort "append-only failure diagnostics drifted" unless (required_failure_diagnostics - actual_failure_names).empty? &&
  actual_failure_names.uniq == actual_failure_names &&
  failure_records.all? { |record| record.fetch("command") == "ruby tools/run-scenario-security-001.rb" }
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
