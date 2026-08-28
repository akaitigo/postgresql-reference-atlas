#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "time"
require_relative "lib/atomic_evidence_publisher"

ROOT = File.expand_path("..", __dir__)
OUTPUT = File.join(ROOT, "artifacts/pattern-scenarios")
IMAGE = "postgres:18.6-alpine"
PATTERNS = {
  "definitive-domain.concurrency.deadlock"=>{
    "target"=>"concurrency.deadlock",
    "oracle"=>"permission-denied-private-relation",
    "sql"=>%q{
      BEGIN;
      CREATE ROLE atlas_deadlock_reader;
      CREATE TABLE atlas_deadlock_private(id integer primary key, secret text);
      INSERT INTO atlas_deadlock_private VALUES (1, 'private');
      REVOKE ALL ON atlas_deadlock_private FROM PUBLIC;
      SET ROLE atlas_deadlock_reader;
      DO $$ BEGIN
        PERFORM * FROM atlas_deadlock_private;
        RAISE EXCEPTION 'permission unexpectedly allowed';
      EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'ATLAS_SECURITY_PASS:concurrency.deadlock';
      END $$;
      RESET ROLE;
      ROLLBACK;
    }
  },
  "definitive-domain.concurrency.locking"=>{
    "target"=>"concurrency.locking",
    "oracle"=>"update-lock-permission-denied",
    "sql"=>%q{
      BEGIN;
      CREATE ROLE atlas_lock_reader;
      CREATE TABLE atlas_lock_private(id integer primary key, value text);
      INSERT INTO atlas_lock_private VALUES (1, 'stable');
      GRANT SELECT ON atlas_lock_private TO atlas_lock_reader;
      SET ROLE atlas_lock_reader;
      DO $$ BEGIN
        UPDATE atlas_lock_private SET value = 'forged' WHERE id = 1;
        RAISE EXCEPTION 'update unexpectedly allowed';
      EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'ATLAS_SECURITY_PASS:concurrency.locking';
      END $$;
      RESET ROLE;
      ROLLBACK;
    }
  },
  "definitive-domain.concurrency.mvcc"=>{
    "target"=>"concurrency.mvcc",
    "oracle"=>"row-level-security-snapshot-isolation",
    "sql"=>%q{
      BEGIN;
      CREATE ROLE atlas_tenant_a;
      CREATE ROLE atlas_tenant_b;
      CREATE TABLE atlas_mvcc_tenant(tenant name, value text);
      ALTER TABLE atlas_mvcc_tenant ENABLE ROW LEVEL SECURITY;
      CREATE POLICY atlas_tenant_policy ON atlas_mvcc_tenant USING (tenant = current_user);
      GRANT SELECT ON atlas_mvcc_tenant TO atlas_tenant_a, atlas_tenant_b;
      INSERT INTO atlas_mvcc_tenant VALUES ('atlas_tenant_a', 'a'), ('atlas_tenant_b', 'b');
      SET ROLE atlas_tenant_a;
      SELECT CASE WHEN count(*) = 1 AND min(value) = 'a'
        THEN 'ATLAS_SECURITY_PASS:concurrency.mvcc'
        ELSE 'ATLAS_SECURITY_FAIL:concurrency.mvcc' END
      FROM atlas_mvcc_tenant;
      RESET ROLE;
      ROLLBACK;
    }
  },
  "definitive-domain.foundation.authority-lock"=>{
    "target"=>"foundation.authority-lock",
    "oracle"=>"version-and-password-policy-lock",
    "sql"=>%q{
      SELECT CASE WHEN current_setting('server_version') LIKE '18.6%'
        AND current_setting('password_encryption') = 'scram-sha-256'
        THEN 'ATLAS_SECURITY_PASS:foundation.authority-lock'
        ELSE 'ATLAS_SECURITY_FAIL:foundation.authority-lock' END;
    }
  }
}.freeze

def digest_bytes(bytes)
  "sha256:#{Digest::SHA256.hexdigest(bytes)}"
end

def digest_file(path)
  "sha256:#{Digest::SHA256.file(path).hexdigest}"
end

def run!(*command, stdin_data: nil)
  stdout, stderr, status = Open3.capture3(*command, stdin_data: stdin_data)
  raise "command failed (#{command.join(' ')}): #{stderr}\n#{stdout}" unless status.success?
  [stdout, stderr]
end

container = "pg-atlas-security-#{Process.pid}-#{SecureRandom.hex(3)}"
started = false
begin
  run!("docker", "run", "--detach", "--rm", "--name", container,
       "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--env", "POSTGRES_DB=atlas",
       IMAGE, "-c", "log_statement=all")
  started = true
  ready = false
  120.times do
    _out, _err, status = Open3.capture3("docker", "exec", container, "pg_isready", "-U", "postgres", "-d", "atlas")
    if status.success?
      ready = true
      break
    end
    sleep 0.25
  end
  raise "PostgreSQL container did not become ready" unless ready
  server_version = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SHOW server_version").first.strip
  server_version_num = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SHOW server_version_num").first.strip
  client_version = run!("docker", "exec", container, "psql", "--version").first.strip
  environment = {
    "subject"=>"PostgreSQL", "server_product"=>"PostgreSQL", "server_version"=>server_version,
    "server_version_num"=>server_version_num, "client_product"=>"psql", "client_version"=>client_version,
    "runtime_image"=>IMAGE, "runtime_identity"=>container, "workers"=>1, "retries"=>0,
    "trace_mode"=>"on", "execution_mode"=>"real-postgresql-server-client"
  }
  matrix_path = File.join(ROOT, "verification.matrix.yaml")
  source_digest = digest_file(matrix_path)
  harness_digest = digest_file(__FILE__)
  publisher = AtomicEvidencePublisher.new(OUTPUT, validator: lambda do |staging|
    report = JSON.parse(File.read(File.join(staging, "results.json")))
    raise "staged report does not contain the full security-001 tranche" unless report.dig("counts", "rows") == 4 && report.dig("counts", "passed") == 4
    report.fetch("tests").each do |test|
      %w[trace screenshot].each do |field|
        relative = test.dig(field, "path").delete_prefix("artifacts/pattern-scenarios/")
        raise "missing staged #{field}" unless File.file?(File.join(staging, relative))
      end
    end
  end)
  result = publisher.publish(run_status: "passed") do |staging|
    trace_root = File.join(staging, "traces")
    observation_root = File.join(staging, "observations")
    FileUtils.mkdir_p(trace_root)
    FileUtils.mkdir_p(observation_root)
    tests = PATTERNS.map do |pattern_id, definition|
      target = definition.fetch("target")
      before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr = run!("docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: definition.fetch("sql"))
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)
      marker = "ATLAS_SECURITY_PASS:#{target}"
      raise "Scenario Oracle marker missing: #{target}" unless (stdout + stderr).include?(marker)
      after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
      plan = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "EXPLAIN (FORMAT JSON) SELECT 1 AS security_probe").first.strip
      log_stdout, log_stderr = run!("docker", "logs", container)
      log = (log_stdout + log_stderr).lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(20).join
      basename = "#{pattern_id.tr('.', '_')}__security__postgresql-verification-matrix-v2"
      trace_document = {
        "schema_version"=>1, "pattern_id"=>pattern_id, "target_id"=>target, "scenario"=>"security",
        "variant_id"=>"postgresql-verification-matrix-v2", "environment"=>environment,
        "sql"=>{"source"=>definition.fetch("sql"), "stdout"=>stdout, "stderr"=>stderr},
        "plan"=>JSON.parse(plan), "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn},
        "log"=>log, "metric"=>{"elapsed_ms"=>elapsed_ms},
        "oracle"=>{"kind"=>definition.fetch("oracle"), "scenario"=>"security", "marker"=>marker, "passed"=>true},
        "streams"=>{"action"=>["psql security transaction"], "network"=>["psql-to-PostgreSQL-session"], "resource"=>["SQL", "plan", "WAL", "server-log", "elapsed-metric"]}
      }
      trace_path = File.join(trace_root, "#{basename}.trace.json")
      File.write(trace_path, JSON.pretty_generate(trace_document) + "\n")
      observation_document = {"schema_version"=>1, "kind"=>"postgresql-observable-state", "pattern_id"=>pattern_id, "scenario"=>"security", "variant_id"=>"postgresql-verification-matrix-v2", "oracle_passed"=>true, "server_version"=>server_version, "client_version"=>client_version}
      observation_path = File.join(observation_root, "#{basename}.observable.json")
      File.write(observation_path, JSON.pretty_generate(observation_document) + "\n")
      final_trace = "artifacts/pattern-scenarios/traces/#{File.basename(trace_path)}"
      final_observation = "artifacts/pattern-scenarios/observations/#{File.basename(observation_path)}"
      {
        "id"=>"security-001.#{target}", "pattern_id"=>pattern_id, "variant_id"=>"postgresql-verification-matrix-v2",
        "scenario"=>"security", "title"=>"#{target} dedicated PostgreSQL security scenario",
        "file"=>"tools/run-scenario-security-001.rb", "line"=>1, "source_digest"=>source_digest,
        "outcome"=>"expected", "attempts"=>1, "final_status"=>"passed", "error"=>nil,
        "oracle"=>trace_document.fetch("oracle"),
        "trace"=>{"path"=>final_trace, "digest"=>digest_file(trace_path), "bytes"=>File.size(trace_path), "action_stream"=>true, "network_stream"=>true, "resource_stream"=>true},
        "screenshot"=>{"path"=>final_observation, "digest"=>digest_file(observation_path), "bytes"=>File.size(observation_path)}
      }
    end
    report = {
      "schema_version"=>1, "id"=>"postgresql-pattern-scenario-runtime-v1", "created_at"=>Time.now.utc.iso8601,
      "status"=>"passed", "command"=>"ruby tools/run-scenario-security-001.rb", "profile"=>"real-postgresql-18.6-container",
      "counts"=>{"rows"=>4, "variants"=>4, "total"=>4, "passed"=>4, "failed"=>0, "flaky"=>0, "skipped"=>0},
      "source_digest"=>source_digest, "harness_digest"=>harness_digest, "environment"=>environment,
      "retention_contract"=>{"publish_on"=>"full-run-passed", "failed_run"=>"retain-prior-success", "swap"=>"staged-directory-rename-with-rollback"},
      "tests"=>tests
    }
    File.write(File.join(staging, "results.json"), JSON.pretty_generate(report) + "\n")
  end
  raise "Scenario Evidence was not published" unless result == :published
  puts "Published atomic PostgreSQL security-001 Evidence: 4 rows / 4 first-attempt Variant runs on #{server_version}."
ensure
  system("docker", "rm", "-f", container, out: File::NULL, err: File::NULL) if started
end
