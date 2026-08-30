#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_scenario_oracles"

marker = "ATLAS_SECURITY_PASS:performance.index"
observed_failure = {
  "server_version"=>"18.6",
  "before_digest"=>"abc123",
  "after_digest"=>"abc123",
  "tenant_rows"=>200,
  "billed_visible_rows"=>200,
  "index_bytes"=>24633344,
  "heap_bytes"=>23412736,
  "index_predicate"=>"billed",
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Seq Scan",
      "Relation Name"=>"atlas_perf_index_secure",
      "Filter"=>"(((tenant)::text = 'atlas_perf_index_reader'::text) AND billed)",
      "Actual Rows"=>200.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>2858
    }
  }],
  "plan_has_index"=>false,
  "security_rejected"=>true,
  "oracle_marker"=>marker,
  "verdict"=>"fail"
}

abort "observed performance.index failure was incorrectly accepted" if SecurityScenarioOracles.performance_index_pass?(observed_failure, marker: marker)

boolean_spoof = observed_failure.merge(
  "plan_has_index"=>true,
  "verdict"=>"pass"
)
abort "boolean-spoofed seq scan was incorrectly accepted" if SecurityScenarioOracles.performance_index_pass?(boolean_spoof, marker: marker)

wrong_index = observed_failure.merge(
  "billed_visible_rows"=>100,
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Index Only Scan",
      "Relation Name"=>"atlas_perf_index_secure",
      "Index Name"=>"atlas_perf_index_other_idx",
      "Index Cond"=>"tenant = atlas_perf_index_reader",
      "Actual Rows"=>100.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>42
    }
  }],
  "verdict"=>"pass"
)
abort "wrong-index plan was incorrectly accepted" if SecurityScenarioOracles.performance_index_pass?(wrong_index, marker: marker)

wrong_partial_predicate = observed_failure.merge(
  "billed_visible_rows"=>100,
  "index_predicate"=>"(NOT billed)",
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Index Only Scan",
      "Relation Name"=>"atlas_perf_index_secure",
      "Index Name"=>"atlas_perf_index_billed_idx",
      "Index Cond"=>"tenant = atlas_perf_index_reader",
      "Actual Rows"=>100.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>42
    }
  }],
  "verdict"=>"pass"
)
abort "wrong partial-index predicate was incorrectly accepted" if SecurityScenarioOracles.performance_index_pass?(wrong_partial_predicate, marker: marker)

tenant_rows_shrink = observed_failure.merge(
  "tenant_rows"=>100,
  "billed_visible_rows"=>100,
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Bitmap Heap Scan",
      "Relation Name"=>"atlas_perf_index_secure",
      "Recheck Cond"=>"(tenant = 'atlas_perf_index_reader'::text) AND billed",
      "Actual Rows"=>100.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>42,
      "Plans"=>[{
        "Node Type"=>"Bitmap Index Scan",
        "Index Name"=>"atlas_perf_index_billed_idx",
        "Index Cond"=>"tenant = atlas_perf_index_reader",
        "Actual Rows"=>100.0,
        "Actual Loops"=>1,
        "Shared Read Blocks"=>4
      }]
    }
  }],
  "verdict"=>"pass"
)
abort "tenant_rows shrink was incorrectly accepted" if SecurityScenarioOracles.performance_index_pass?(tenant_rows_shrink, marker: marker)

count_self_report = observed_failure.merge(
  "billed_visible_rows"=>100,
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Bitmap Heap Scan",
      "Relation Name"=>"atlas_perf_index_secure",
      "Recheck Cond"=>"(tenant = 'atlas_perf_index_reader'::text) AND billed",
      "Actual Rows"=>200.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>42,
      "Plans"=>[{
        "Node Type"=>"Bitmap Index Scan",
        "Index Name"=>"atlas_perf_index_billed_idx",
        "Index Cond"=>"tenant = atlas_perf_index_reader",
        "Actual Rows"=>200.0,
        "Actual Loops"=>1,
        "Shared Read Blocks"=>4
      }]
    }
  }],
  "verdict"=>"pass"
)
abort "count self-report mismatch was incorrectly accepted" if SecurityScenarioOracles.performance_index_pass?(count_self_report, marker: marker)

digest_mismatch = observed_failure.merge(
  "after_digest"=>"def456",
  "billed_visible_rows"=>100,
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Bitmap Heap Scan",
      "Relation Name"=>"atlas_perf_index_secure",
      "Recheck Cond"=>"(tenant = 'atlas_perf_index_reader'::text) AND billed",
      "Actual Rows"=>100.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>42,
      "Plans"=>[{
        "Node Type"=>"Bitmap Index Scan",
        "Index Name"=>"atlas_perf_index_billed_idx",
        "Index Cond"=>"tenant = atlas_perf_index_reader",
        "Actual Rows"=>100.0,
        "Actual Loops"=>1,
        "Shared Read Blocks"=>4
      }]
    }
  }],
  "verdict"=>"pass"
)
abort "digest mismatch was incorrectly accepted" if SecurityScenarioOracles.performance_index_pass?(digest_mismatch, marker: marker)

index_path_missing = observed_failure.merge(
  "billed_visible_rows"=>100,
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Sort",
      "Actual Rows"=>100.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>42
    }
  }],
  "verdict"=>"pass"
)
abort "index-path-missing plan was incorrectly accepted" if SecurityScenarioOracles.performance_index_pass?(index_path_missing, marker: marker)

passing_shape = observed_failure.merge(
  "billed_visible_rows"=>100,
  "plan"=>[{
    "Plan"=>{
      "Node Type"=>"Bitmap Heap Scan",
      "Relation Name"=>"atlas_perf_index_secure",
      "Recheck Cond"=>"(tenant = 'atlas_perf_index_reader'::text) AND billed",
      "Actual Rows"=>100.0,
      "Actual Loops"=>1,
      "Shared Hit Blocks"=>42,
      "Plans"=>[{
        "Node Type"=>"Bitmap Index Scan",
        "Index Name"=>"atlas_perf_index_billed_idx",
        "Index Cond"=>"tenant = atlas_perf_index_reader",
        "Actual Rows"=>100.0,
        "Actual Loops"=>1,
        "Shared Read Blocks"=>4
      }]
    }
  }],
  "verdict"=>"pass"
)
abort "indexed first-attempt pass shape was incorrectly rejected" unless SecurityScenarioOracles.performance_index_pass?(passing_shape, marker: marker)

puts "performance.index oracle contractを検証しました: all-even tenant fixture, count self-report, tenant shrink, digest mismatch, index-path-missing, boolean spoof, wrong-index, wrong-partial-predicate negatives rejected and indexed first-attempt pass shape accepted"
