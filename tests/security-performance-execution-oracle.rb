#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../tools/lib/security_scenario_oracles"

fixture_path = File.expand_path("fixtures/security-performance-execution-observed-seq-scan.json", __dir__)
fixture = JSON.parse(File.read(fixture_path))
observed_failure = fixture.fetch("actual_result")
marker = observed_failure.fetch("oracle_marker")

abort "observed performance.execution failure was incorrectly accepted" if SecurityScenarioOracles.performance_execution_pass?(observed_failure, marker: marker)

boolean_spoof = observed_failure.merge(
  "plan_has_index"=>true,
  "verdict"=>"pass"
)
abort "boolean-spoofed seq scan was incorrectly accepted" if SecurityScenarioOracles.performance_execution_pass?(boolean_spoof, marker: marker)

wrong_index = observed_failure.merge(
  "plan_has_index"=>true,
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Index Only Scan",
      "Relation Name"=>"atlas_perf_execution_secure",
      "Index Name"=>"atlas_perf_execution_other_idx",
      "Actual Rows"=>200.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>42
    }
  }],
  "verdict"=>"pass"
)
abort "wrong-index plan was incorrectly accepted" if SecurityScenarioOracles.performance_execution_pass?(wrong_index, marker: marker)

passing_shape = observed_failure.merge(
  "plan_has_index"=>false,
  "plan_has_actual_rows"=>false,
  "plan_has_buffers"=>false,
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Index Only Scan",
      "Relation Name"=>"atlas_perf_execution_secure",
      "Index Name"=>"atlas_perf_execution_tenant_idx",
      "Actual Rows"=>200.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>42
    }
  }],
  "verdict"=>"pass"
)
abort "indexed first-attempt pass shape was incorrectly rejected" unless SecurityScenarioOracles.performance_execution_pass?(passing_shape, marker: marker)

puts "performance.execution oracle contractを検証しました: observed seq-scan, boolean spoof, wrong-index negatives rejected and indexed first-attempt pass shape accepted"
