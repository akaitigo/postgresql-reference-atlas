#!/usr/bin/env ruby
# frozen_string_literal: true

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
oracle_source = File.read(File.expand_path("../tools/lib/security_scenario_oracles.rb", __dir__))

index_section = source[/def performance_index_security_execution\(container\)(.*?)^end$/m, 1]
planner_section = source[/def performance_planner_security_execution\(container\)(.*?)^end$/m, 1]

abort "performance.index section is missing" unless index_section
abort "performance.planner section is missing" unless planner_section

def assert_includes!(haystack, needle, message)
  abort message unless haystack.include?(needle)
end

def assert_excludes!(haystack, needle, message)
  abort message if haystack.include?(needle)
end

assert_includes!(oracle_source, "def performance_index_predicates(result, marker:)", "performance.index predicate helper is missing")
assert_includes!(oracle_source, "def performance_planner_predicates(result, marker:)", "performance.planner predicate helper is missing")

assert_includes!(index_section, "predicates = SecurityScenarioOracles.performance_index_predicates(result, marker: marker)", "performance.index does not compute structured predicates")
assert_includes!(index_section, "SecurityFailureDiagnostics::ScenarioOracleFailure.new(", "performance.index does not raise structured Oracle failure")
assert_includes!(index_section, 'failed_row: "closure.definitive-domain.performance.index.security"', "performance.index failed_row binding drifted")
assert_includes!(index_section, 'target: "performance.index"', "performance.index target binding drifted")
assert_includes!(index_section, 'oracle_error: "performance.index security Oracle failed"', "performance.index oracle_error binding drifted")
assert_includes!(index_section, "actual_result: result", "performance.index actual_result binding drifted")
assert_includes!(index_section, "oracle_predicates: predicates", "performance.index predicate binding drifted")
assert_excludes!(index_section, 'raise "performance.index security Oracle failed"', "performance.index still uses generic RuntimeError")

assert_includes!(planner_section, "EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON)", "performance.planner explain must capture actual rows and buffers")
assert_includes!(planner_section, "predicates = SecurityScenarioOracles.performance_planner_predicates(result, marker: marker)", "performance.planner does not compute structured predicates")
assert_includes!(planner_section, "SecurityFailureDiagnostics::ScenarioOracleFailure.new(", "performance.planner does not raise structured Oracle failure")
assert_includes!(planner_section, 'failed_row: "closure.definitive-domain.performance.planner.security"', "performance.planner failed_row binding drifted")
assert_includes!(planner_section, 'target: "performance.planner"', "performance.planner target binding drifted")
assert_includes!(planner_section, 'oracle_error: "performance.planner security Oracle failed"', "performance.planner oracle_error binding drifted")
assert_includes!(planner_section, "actual_result: result", "performance.planner actual_result binding drifted")
assert_includes!(planner_section, "oracle_predicates: predicates", "performance.planner predicate binding drifted")
assert_excludes!(planner_section, 'raise "performance.planner security Oracle failed"', "performance.planner still uses generic RuntimeError")
assert_excludes!(planner_section, "THEN 'pass'\n        THEN 'pass'", "performance.planner SQL CASE contains duplicate THEN")

puts "performance structured failure contractを検証しました: index/planner both emit ScenarioOracleFailure with actual result + predicates and planner captures ANALYZE/BUFFERS/WAL"
