#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"
require_relative "../tools/lib/security_runtime_readiness_contract"

plan = SecurityScenarioTranche.load_plan
root = SecurityRuntimeReadinessContract::ROOT
token_env = SecurityRuntimeReadinessContract::SLOT_TOKEN_ENV
now = Time.utc(2026, 8, 31, 12, 0, 0)
ready_env = { token_env=>"security-slot-001" }
ready_measurements = { "free_gib"=>4.5, "docker_active_containers"=>0 }

ready = SecurityRuntimeReadinessContract.evaluate_live_preflight!(
  plan: plan, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root, measurements: ready_measurements
)
abort "live preflight should be ready on the pass path" unless ready.fetch("status") == "ready"
SecurityRuntimeReadinessContract.verify_preflight!(ready, plan: plan, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root)

free_drift = SecurityRuntimeReadinessContract.evaluate_live_preflight!(
  plan: plan, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root,
  measurements: { "free_gib"=>3.9, "docker_active_containers"=>0 }
)
abort "free<4GiB must block runtime" unless free_drift.fetch("status") == "blocked" && free_drift.fetch("failures").include?("insufficient-free-space")
begin
  SecurityRuntimeReadinessContract.verify_runnable!(plan: plan, preflight: free_drift, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root)
  abort "free<4GiB runtime preflight was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("insufficient-free-space")
end

docker_drift = SecurityRuntimeReadinessContract.evaluate_live_preflight!(
  plan: plan, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root,
  measurements: { "free_gib"=>4.5, "docker_active_containers"=>1 }
)
abort "docker>0 must block runtime" unless docker_drift.fetch("status") == "blocked" && docker_drift.fetch("failures").include?("docker-active-containers-not-zero")

stale = JSON.parse(JSON.generate(ready))
stale["measured_at"] = (now - 61).utc.iso8601
stale["status"] = "blocked"
stale["failures"] = ["stale-preflight"]
begin
  SecurityRuntimeReadinessContract.verify_runnable!(plan: plan, preflight: stale, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root)
  abort "stale runtime preflight runnable path was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("stale-preflight")
end

reused_token = JSON.parse(JSON.generate(ready))
reused_token["status"] = "blocked"
reused_token["failures"] = ["slot-token-missing-or-mismatched"]
begin
  SecurityRuntimeReadinessContract.verify_runnable!(
    plan: plan, preflight: reused_token, env: { token_env=>"security-slot-002" },
    now: now, pid: 5150, repo_root: root, cwd: root
  )
  abort "runtime preflight token reuse was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("slot-token-missing-or-mismatched")
end

other_repo = JSON.parse(JSON.generate(ready))
other_repo["repo_root"] = "/tmp/other-repo"
other_repo["cwd"] = "/tmp/other-repo"
other_repo["status"] = "blocked"
other_repo["failures"] = ["repo-root-confinement-failed", "cwd-confinement-failed"]
begin
  SecurityRuntimeReadinessContract.verify_preflight!(
    other_repo, plan: plan, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root
  )
  abort "other repo runtime preflight was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("repo root drifted")
end

other_pid = JSON.parse(JSON.generate(ready))
other_pid["pid"] = 9999
other_pid["status"] = "blocked"
other_pid["failures"] = ["pid-mismatch"]
begin
  SecurityRuntimeReadinessContract.verify_preflight!(other_pid, plan: plan, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root)
  abort "other pid runtime preflight was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("pid drifted")
end

status_hand_edit = JSON.parse(JSON.generate(free_drift))
status_hand_edit["status"] = "ready"
begin
  SecurityRuntimeReadinessContract.verify_preflight!(status_hand_edit, plan: plan, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root)
  abort "runtime preflight status hand-edit was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("status drifted")
end

row_shrink = JSON.parse(JSON.generate(ready))
row_shrink["row_ids"] = row_shrink.fetch("row_ids").first(3)
row_shrink["status"] = "blocked"
row_shrink["failures"] = ["row-ids-drift"]
begin
  SecurityRuntimeReadinessContract.verify_preflight!(row_shrink, plan: plan, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root)
  abort "runtime preflight row shrink was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("row_ids drifted")
end

output_shrink = JSON.parse(JSON.generate(ready))
output_shrink["expected_outputs"] = output_shrink.fetch("expected_outputs").first(8)
output_shrink["status"] = "blocked"
output_shrink["failures"] = ["expected-outputs-drift"]
begin
  SecurityRuntimeReadinessContract.verify_preflight!(output_shrink, plan: plan, env: ready_env, now: now, pid: 5150, repo_root: root, cwd: root)
  abort "runtime preflight output shrink was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("expected outputs drifted")
end

puts "security runtime live preflightを検証しました: same-run token/root/pid/timestamp/disk/docker gating is live, and reuse/stale/other-repo/other-pid/free<4/docker>0/status-hand-edit/output-row shrink regressions are rejected"
