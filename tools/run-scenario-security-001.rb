#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "base64"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "time"
require_relative "lib/atomic_evidence_publisher"

ROOT = File.expand_path("..", __dir__)
OUTPUT = File.join(ROOT, "artifacts/pattern-scenarios")
IMAGE = "postgres:18.6-alpine"
PG18_IMAGE = "postgres:18.6-alpine@sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2"
PG17_IMAGE = "postgres:17.11-alpine@sha256:18cfe3ef5e6815560c98237d6216d1e5119702fb0f3894c8785dd58b8bbe5d73"
COMPATIBILITY_IMAGES = [
  "postgres:14.24-alpine@sha256:727876d274666da0b92a445390ba093c84b8e9f8343e1c53cd4e9a7ab2d85310",
  "postgres:15.19-alpine3.23@sha256:b0dc4a8dc256b963ee25867843d9fd366850e327e4a2a65ccb3c47262d092973",
  "postgres:16.15-alpine3.23@sha256:421b84e07a72bb8f3715f20501a1fdbe1219aad1fa4af7786a49d9a3f2480296",
  PG17_IMAGE,
  PG18_IMAGE
].freeze
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
  },
  "definitive-domain.foundation.version-lock"=>{
    "target"=>"foundation.version-lock",
    "oracle"=>"exact-server-version-and-scram-default",
    "sql"=>%q{
      SELECT CASE WHEN current_setting('server_version_num') = '180006'
        AND current_setting('password_encryption') = 'scram-sha-256'
        THEN 'ATLAS_SECURITY_PASS:foundation.version-lock'
        ELSE 'ATLAS_SECURITY_FAIL:foundation.version-lock' END;
    }
  },
  "definitive-domain.lifecycle.compatibility-matrix"=>{
    "target"=>"lifecycle.compatibility-matrix",
    "oracle"=>"scram-and-role-boundary-across-14-24-to-18-6",
    "executor"=>"compatibility-matrix",
    "sql"=>%q{
      BEGIN;
      CREATE ROLE atlas_compat_reader LOGIN PASSWORD 'atlas-scenario-only-password';
      CREATE TABLE atlas_compat_private(tenant name NOT NULL, payload text NOT NULL);
      ALTER TABLE atlas_compat_private ENABLE ROW LEVEL SECURITY;
      CREATE POLICY atlas_compat_policy ON atlas_compat_private USING (tenant = current_user);
      GRANT SELECT ON atlas_compat_private TO atlas_compat_reader;
      INSERT INTO atlas_compat_private VALUES ('atlas_compat_reader', 'visible'), ('postgres', 'hidden');
      SET ROLE atlas_compat_reader;
      SELECT CASE WHEN count(*) = 1 AND min(payload) = 'visible'
        THEN 'ATLAS_SECURITY_PASS:lifecycle.compatibility-matrix'
        ELSE 'ATLAS_SECURITY_FAIL:lifecycle.compatibility-matrix' END
      FROM atlas_compat_private;
      DO $$ BEGIN
        DELETE FROM atlas_compat_private;
        RAISE EXCEPTION 'delete unexpectedly allowed';
      EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'ATLAS_SECURITY_PASS:lifecycle.compatibility-matrix';
      END $$;
      RESET ROLE;
      ROLLBACK;
    }
  },
  "definitive-domain.lifecycle.pg-upgrade"=>{
    "target"=>"lifecycle.pg-upgrade",
    "oracle"=>"scram-rls-and-acl-survive-17-to-18-binary-upgrade",
    "executor"=>"pg-upgrade",
    "file"=>"labs/pg-upgrade/security-verify.sh"
  },
  "definitive-domain.lifecycle.schema-migration"=>{
    "target"=>"lifecycle.schema-migration",
    "oracle"=>"unauthorized-ddl-rejected-during-schema-migration",
    "sql"=>%q{
      BEGIN;
      CREATE ROLE atlas_migration_reader;
      CREATE SCHEMA atlas_migration AUTHORIZATION postgres;
      CREATE TABLE atlas_migration.secure_record(id integer PRIMARY KEY, payload text NOT NULL);
      INSERT INTO atlas_migration.secure_record VALUES (1, 'stable');
      GRANT USAGE ON SCHEMA atlas_migration TO atlas_migration_reader;
      GRANT SELECT ON atlas_migration.secure_record TO atlas_migration_reader;
      SET ROLE atlas_migration_reader;
      DO $$ BEGIN
        ALTER TABLE atlas_migration.secure_record ADD COLUMN forged boolean;
        RAISE EXCEPTION 'ddl unexpectedly allowed';
      EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'ATLAS_SECURITY_PASS:lifecycle.schema-migration';
      END $$;
      SELECT CASE WHEN count(*) = 1 AND min(payload) = 'stable'
        THEN 'ATLAS_SECURITY_PASS:lifecycle.schema-migration'
        ELSE 'ATLAS_SECURITY_FAIL:lifecycle.schema-migration' END
      FROM atlas_migration.secure_record;
      RESET ROLE;
      ROLLBACK;
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

def wait_for_postgres(container)
  consecutive = 0
  120.times do
    out, _err, status = Open3.capture3(
      "docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT 1"
    )
    if status.success? && out.strip == "1"
      consecutive += 1
      return if consecutive == 2
    else
      consecutive = 0
    end
    sleep 0.25
  end
  raise "PostgreSQL container did not become ready for two consecutive SQL sessions: #{container}"
end

def default_execution(container, definition)
  before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr = run!("docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: definition.fetch("sql"))
  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)
  after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  plan = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "EXPLAIN (FORMAT JSON) SELECT 1 AS security_probe").first.strip
  log_stdout, log_stderr = run!("docker", "logs", container)
  {
    "sql"=>{"source"=>definition.fetch("sql"), "stdout"=>stdout, "stderr"=>stderr},
    "plan"=>JSON.parse(plan), "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn},
    "log"=>(log_stdout + log_stderr).lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(30).join,
    "metric"=>{"elapsed_ms"=>elapsed_ms}, "oracle_output"=>stdout + stderr,
    "runtime"=>{"server_versions"=>["18.6"], "containers"=>[container]}
  }
end

def compatibility_execution(definition)
  expected_versions = %w[14.24 15.19 16.15 17.11 18.6]
  observations = []
  COMPATIBILITY_IMAGES.each_with_index do |image, index|
    container = "pg-atlas-security-compat-#{Process.pid}-#{index}-#{SecureRandom.hex(2)}"
    started = false
    begin
      run!("docker", "run", "--detach", "--rm", "--name", container,
           "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--env", "POSTGRES_DB=atlas",
           image, "-c", "log_statement=all")
      started = true
      wait_for_postgres(container)
      before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr = run!("docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: definition.fetch("sql"))
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)
      version = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SHOW server_version").first.strip
      client_version = run!("docker", "exec", container, "psql", "--version").first.strip
      password_encryption = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SHOW password_encryption").first.strip
      after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
      plan = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "EXPLAIN (FORMAT JSON) SELECT current_setting('server_version')").first.strip
      log_stdout, log_stderr = run!("docker", "logs", container)
      marker = "ATLAS_SECURITY_PASS:lifecycle.compatibility-matrix"
      raise "Compatibility security Oracle marker missing: #{version}" unless (stdout + stderr).scan(marker).length >= 2
      observations << {
        "image"=>image, "server_version"=>version, "client_version"=>client_version,
        "password_encryption"=>password_encryption, "role_boundary_passed"=>true,
        "stdout"=>stdout, "stderr"=>stderr,
        "plan"=>JSON.parse(plan), "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn},
        "log"=>(log_stdout + log_stderr).lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(20).join,
        "elapsed_ms"=>elapsed_ms
      }
    ensure
      system("docker", "rm", "-f", container, out: File::NULL, err: File::NULL) if started
    end
  end
  raise "Compatibility security version denominator mismatch" unless observations.map { |row| row.fetch("server_version") } == expected_versions
  raise "Compatibility security SCRAM default mismatch" unless observations.all? { |row| row.fetch("password_encryption") == "scram-sha-256" }
  {
    "sql"=>{"source"=>definition.fetch("sql"), "stdout"=>JSON.generate(observations.map { |row| row.slice("server_version", "client_version", "password_encryption", "role_boundary_passed") }), "stderr"=>""},
    "plan"=>observations.map { |row| {"server_version"=>row.fetch("server_version"), "plan"=>row.fetch("plan")} },
    "wal"=>observations.map { |row| {"server_version"=>row.fetch("server_version")}.merge(row.fetch("wal")) },
    "log"=>observations.map { |row| "#{row.fetch('server_version')}:\n#{row.fetch('log')}" }.join("\n"),
    "metric"=>{"elapsed_ms_by_version"=>observations.to_h { |row| [row.fetch("server_version"), row.fetch("elapsed_ms")] }},
    "oracle_output"=>"ATLAS_SECURITY_PASS:lifecycle.compatibility-matrix",
    "runtime"=>{"server_versions"=>expected_versions, "images"=>COMPATIBILITY_IMAGES}
  }
end

def pg_upgrade_execution
  tag = "pg-atlas-security-upgrade:#{Process.pid}-#{SecureRandom.hex(3)}"
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    run!("docker", "build", "-q", "-f", File.join(ROOT, "labs/pg-upgrade/Dockerfile.security"), "-t", tag,
         "--build-arg", "PG17_IMAGE=#{PG17_IMAGE}", "--build-arg", "PG18_IMAGE=#{PG18_IMAGE}",
         File.join(ROOT, "labs/pg-upgrade"))
    stdout, stderr = run!("docker", "run", "--rm", "--tmpfs", "/work:rw,exec,size=1g", tag)
    result = JSON.parse(stdout)
    raise "pg_upgrade security Oracle failed" unless result.fetch("verdict") == "pass" && result.fetch("old_version") == "17.11" && result.fetch("new_version") == "18.6" && result.fetch("verifier_digest_preserved") == true && result.fetch("visible_rows") == 1 && result.fetch("update_denied") == true
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)
    {
      "sql"=>{"source"=>File.read(File.join(ROOT, "labs/pg-upgrade/security-verify.sh")), "stdout"=>stdout, "stderr"=>stderr},
      "plan"=>JSON.parse(Base64.decode64(result.fetch("plan_base64"))),
      "wal"=>{"old_lsn"=>result.fetch("old_lsn"), "new_lsn"=>result.fetch("new_lsn")},
      "log"=>stderr.lines.last(80).join, "metric"=>{"elapsed_ms"=>elapsed_ms},
      "oracle_output"=>"ATLAS_SECURITY_PASS:lifecycle.pg-upgrade",
      "runtime"=>{"server_versions"=>[result.fetch("old_version"), result.fetch("new_version")], "base_images"=>[PG17_IMAGE, PG18_IMAGE], "ephemeral_image"=>tag}
    }
  ensure
    system("docker", "image", "rm", tag, out: File::NULL, err: File::NULL)
  end
end

container = "pg-atlas-security-#{Process.pid}-#{SecureRandom.hex(3)}"
started = false
begin
  run!("docker", "run", "--detach", "--rm", "--name", container,
       "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--env", "POSTGRES_DB=atlas",
       IMAGE, "-c", "log_statement=all")
  started = true
  wait_for_postgres(container)
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
    expected = PATTERNS.length
    raise "staged report does not contain every completed security row" unless report.dig("counts", "rows") == expected && report.dig("counts", "passed") == expected
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
      marker = "ATLAS_SECURITY_PASS:#{target}"
      execution = case definition["executor"]
                  when "compatibility-matrix" then compatibility_execution(definition)
                  when "pg-upgrade" then pg_upgrade_execution
                  else default_execution(container, definition)
                  end
      raise "Scenario Oracle marker missing: #{target}" unless execution.fetch("oracle_output").include?(marker)
      basename = "#{pattern_id.tr('.', '_')}__security__postgresql-verification-matrix-v2"
      trace_document = {
        "schema_version"=>1, "pattern_id"=>pattern_id, "target_id"=>target, "scenario"=>"security",
        "variant_id"=>"postgresql-verification-matrix-v2", "environment"=>environment.merge("row_runtime"=>execution.fetch("runtime")),
        "sql"=>execution.fetch("sql"), "plan"=>execution.fetch("plan"), "wal"=>execution.fetch("wal"),
        "log"=>execution.fetch("log"), "metric"=>execution.fetch("metric"),
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
        "id"=>"security-runtime.#{target}", "pattern_id"=>pattern_id, "variant_id"=>"postgresql-verification-matrix-v2",
        "scenario"=>"security", "title"=>"#{target} dedicated PostgreSQL security scenario",
        "file"=>definition.fetch("file", "tools/run-scenario-security-001.rb"), "line"=>1, "source_digest"=>source_digest,
        "outcome"=>"expected", "attempts"=>1, "final_status"=>"passed", "error"=>nil,
        "oracle"=>trace_document.fetch("oracle"),
        "trace"=>{"path"=>final_trace, "digest"=>digest_file(trace_path), "bytes"=>File.size(trace_path), "action_stream"=>true, "network_stream"=>true, "resource_stream"=>true},
        "screenshot"=>{"path"=>final_observation, "digest"=>digest_file(observation_path), "bytes"=>File.size(observation_path)}
      }
    end
    report = {
      "schema_version"=>1, "id"=>"postgresql-pattern-scenario-runtime-v1", "created_at"=>Time.now.utc.iso8601,
      "status"=>"passed", "command"=>"ruby tools/run-scenario-security-001.rb", "profile"=>"real-postgresql-18.6-container",
      "counts"=>{"rows"=>PATTERNS.length, "variants"=>PATTERNS.length, "total"=>PATTERNS.length, "passed"=>PATTERNS.length, "failed"=>0, "flaky"=>0, "skipped"=>0},
      "source_digest"=>source_digest, "harness_digest"=>harness_digest, "environment"=>environment,
      "retention_contract"=>{"publish_on"=>"full-run-passed", "failed_run"=>"retain-prior-success", "swap"=>"staged-directory-rename-with-rollback"},
      "tests"=>tests
    }
    File.write(File.join(staging, "results.json"), JSON.pretty_generate(report) + "\n")
  end
  raise "Scenario Evidence was not published" unless result == :published
  puts "Published atomic PostgreSQL security Evidence: #{PATTERNS.length} rows / #{PATTERNS.length} first-attempt Variant runs."
ensure
  system("docker", "rm", "-f", container, out: File::NULL, err: File::NULL) if started
end
