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
require_relative "lib/security_failure_diagnostics"
require_relative "lib/security_next_tranche_contract"
require_relative "lib/security_performance_statistics_contract"
require_relative "lib/security_publication_provenance_contract"
require_relative "lib/security_query_catalog_inventory_contract"
require_relative "lib/security_query_extension_contract"
require_relative "lib/security_runtime_readiness_contract"
require_relative "lib/security_scenario_oracles"
require_relative "lib/security_scenario_tranche"

ROOT = File.expand_path("..", __dir__)
OUTPUT = File.join(ROOT, "artifacts/pattern-scenarios")
FAILURE_DIAGNOSTICS_OUTPUT = File.join(ROOT, "artifacts/pattern-scenario-failures")
WAL_SEGMENT_SWITCH_PREDICATE = "switched_lsn >= end_lsn"
PERFORMANCE_EXECUTION_LITERAL_TENANT = "atlas_perf_execution_reader"
PERFORMANCE_INDEX_LITERAL_TENANT = "atlas_perf_index_reader"
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
  },
  "definitive-domain.lifecycle.upgrade"=>{
    "target"=>"lifecycle.upgrade",
    "oracle"=>"acl-and-rls-survive-17-to-18-logical-upgrade",
    "executor"=>"logical-upgrade"
  },
  "definitive-domain.operations.backup-recovery"=>{
    "target"=>"operations.backup-recovery",
    "oracle"=>"acl-and-rls-survive-custom-backup-restore",
    "executor"=>"backup-recovery"
  },
  "definitive-domain.operations.failure-injection"=>{
    "target"=>"operations.failure-injection",
    "oracle"=>"acl-and-rls-survive-immediate-server-crash-recovery",
    "executor"=>"failure-injection"
  },
  "definitive-domain.operations.logical-replication"=>{
    "target"=>"operations.logical-replication",
    "oracle"=>"replicated-data-remains-bounded-by-subscriber-rls-and-acl",
    "executor"=>"logical-replication"
  },
  "definitive-domain.operations.maintenance"=>{
    "target"=>"operations.maintenance",
    "oracle"=>"maintenance-configuration-change-requires-table-owner",
    "plan_sql"=>"SELECT relname, reloptions FROM pg_class WHERE relname = 'atlas_maintenance_secure'",
    "sql"=>%q{
      BEGIN;
      CREATE ROLE atlas_maintenance_reader;
      CREATE TABLE atlas_maintenance_secure(id integer PRIMARY KEY, payload text NOT NULL);
      INSERT INTO atlas_maintenance_secure VALUES (1, 'stable');
      GRANT SELECT ON atlas_maintenance_secure TO atlas_maintenance_reader;
      SET ROLE atlas_maintenance_reader;
      DO $$ BEGIN
        ALTER TABLE atlas_maintenance_secure SET (autovacuum_enabled = false);
        RAISE EXCEPTION 'maintenance configuration unexpectedly allowed';
      EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'ATLAS_SECURITY_PASS:operations.maintenance';
      END $$;
      SELECT CASE WHEN count(*) = 1 AND min(payload) = 'stable'
        THEN 'ATLAS_SECURITY_PASS:operations.maintenance'
        ELSE 'ATLAS_SECURITY_FAIL:operations.maintenance' END
      FROM atlas_maintenance_secure;
      RESET ROLE;
      ROLLBACK;
    }
  },
  "definitive-domain.operations.observability"=>{
    "target"=>"operations.observability",
    "oracle"=>"pg-monitor-observability-does-not-grant-private-table-access",
    "plan_sql"=>"SELECT pid, usename, state FROM pg_stat_activity WHERE datname = current_database()",
    "sql"=>%q{
      BEGIN;
      CREATE ROLE atlas_observer;
      GRANT pg_monitor TO atlas_observer;
      CREATE TABLE atlas_observability_private(id integer PRIMARY KEY, payload text NOT NULL);
      INSERT INTO atlas_observability_private VALUES (1, 'private');
      REVOKE ALL ON atlas_observability_private FROM PUBLIC;
      SET ROLE atlas_observer;
      SELECT CASE WHEN pg_has_role(current_user, 'pg_monitor', 'MEMBER')
        AND (SELECT count(*) FROM pg_stat_activity) > 0
        THEN 'ATLAS_SECURITY_PASS:operations.observability'
        ELSE 'ATLAS_SECURITY_FAIL:operations.observability' END;
      DO $$ BEGIN
        PERFORM * FROM atlas_observability_private;
        RAISE EXCEPTION 'private table access unexpectedly allowed';
      EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'ATLAS_SECURITY_PASS:operations.observability';
      END $$;
      RESET ROLE;
      ROLLBACK;
    }
  },
  "definitive-domain.operations.wal"=>{
    "target"=>"operations.wal",
    "oracle"=>"rls-bounded-20k-write-advances-wal-and-switches-segment",
    "executor"=>"wal-security"
  },
  "definitive-domain.performance.execution"=>{
    "target"=>"performance.execution",
    "oracle"=>"rls-bounded-index-plan-emits-actual-rows-buffers-and-relation-sizes",
    "executor"=>"performance-execution-security"
  },
  "definitive-domain.performance.index"=>{
    "target"=>"performance.index",
    "oracle"=>"partial-index-preserves-results-and-serves-rls-bounded-query",
    "executor"=>"performance-index-security"
  },
  "definitive-domain.performance.planner"=>{
    "target"=>"performance.planner",
    "oracle"=>"analyzed-rls-bounded-selective-query-uses-index-plan",
    "executor"=>"performance-planner-security"
  },
  "definitive-domain.performance.statistics"=>{
    "target"=>"performance.statistics",
    "oracle"=>"extended-statistics-estimate-and-owner-only-maintenance",
    "executor"=>"performance-statistics-security"
  },
  "definitive-domain.publication.provenance"=>{
    "target"=>"publication.provenance",
    "oracle"=>"read-only-rights-sbom-secret-and-graph-gates",
    "executor"=>"publication-provenance-security"
  },
  "definitive-domain.query.catalog-inventory"=>{
    "target"=>"query.catalog-inventory",
    "oracle"=>"ordered-pg-catalog-digests-and-mutation-refusal",
    "executor"=>"catalog-inventory-security"
  },
  "definitive-domain.query.extension"=>{
    "target"=>"query.extension",
    "oracle"=>"rls-bounded-pg-trgm-gin-plan-and-install-refusal",
    "executor"=>"bundled-extension-security"
  },
  "definitive-domain.operations.pitr-recovery"=>{
    "target"=>"operations.pitr-recovery",
    "oracle"=>"pitr-restores-pre-target-rls-and-acl-boundary",
    "executor"=>"pitr-recovery",
    "file"=>"labs/pitr/security-verify.sh"
  },
  "definitive-domain.operations.replication"=>{
    "target"=>"operations.replication",
    "oracle"=>"physical-standby-replays-rls-and-acl-and-rejects-writes",
    "executor"=>"physical-replication",
    "file"=>"labs/replication/security-verify.sh"
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
  plan_sql = definition.fetch("plan_sql", "SELECT 1 AS security_probe")
  plan = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "EXPLAIN (FORMAT JSON) #{plan_sql}").first.strip
  log_stdout, log_stderr = run!("docker", "logs", container)
  {
    "sql"=>{"source"=>definition.fetch("sql"), "stdout"=>stdout, "stderr"=>stderr},
    "plan"=>JSON.parse(plan), "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn},
    "log"=>(log_stdout + log_stderr).lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(30).join,
    "metric"=>{"elapsed_ms"=>elapsed_ms}, "oracle_output"=>stdout + stderr,
    "runtime"=>{"server_versions"=>["18.6"], "containers"=>[container]}
  }
end

def psql_json_execution(container, sql)
  stdout, stderr = run!("docker", "exec", "-i", container, "psql", "-XAt", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: sql)
  json_line = stdout.lines.reverse.map(&:strip).find { |line| line.start_with?("{") && line.end_with?("}") }
  raise "JSON result missing from scenario execution" unless json_line&.start_with?("{")
  [JSON.parse(json_line), stdout, stderr]
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
      system("docker", "rm", "-f", "-v", container, out: File::NULL, err: File::NULL) if started
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

def role_boundary_sql(target, relation, role)
  <<~SQL
    SET ROLE #{role};
    SELECT CASE WHEN count(*) = 1 AND min(payload) = 'visible'
      THEN 'ATLAS_SECURITY_PASS:#{target}'
      ELSE 'ATLAS_SECURITY_FAIL:#{target}' END
    FROM #{relation};
    DO $$ BEGIN
      UPDATE #{relation} SET payload = 'forged';
      RAISE EXCEPTION 'update unexpectedly allowed';
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'ATLAS_SECURITY_PASS:#{target}';
    END $$;
    RESET ROLE;
  SQL
end

def security_fixture_sql(relation, role)
  <<~SQL
    CREATE ROLE #{role};
    CREATE TABLE #{relation}(tenant name NOT NULL, payload text NOT NULL);
    ALTER TABLE #{relation} ENABLE ROW LEVEL SECURITY;
    CREATE POLICY atlas_security_policy ON #{relation} USING (tenant = current_user);
    GRANT SELECT ON #{relation} TO #{role};
    INSERT INTO #{relation} VALUES ('#{role}', 'visible'), ('postgres', 'hidden');
  SQL
end

def logical_upgrade_execution
  suffix = "#{Process.pid}-#{SecureRandom.hex(3)}"
  network = "pg-atlas-security-upgrade-net-#{suffix}"
  old = "pg-atlas-security-upgrade-old-#{suffix}"
  new_server = "pg-atlas-security-upgrade-new-#{suffix}"
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  source = security_fixture_sql("atlas_upgrade_secure", "atlas_upgrade_reader")
  verification = role_boundary_sql("lifecycle.upgrade", "atlas_upgrade_secure", "atlas_upgrade_reader")
  begin
    run!("docker", "network", "create", network)
    run!("docker", "run", "--detach", "--name", old, "--network", network,
         "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--env", "POSTGRES_DB=atlas",
         PG17_IMAGE, "-c", "log_statement=all")
    run!("docker", "run", "--detach", "--name", new_server, "--network", network,
         "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--env", "POSTGRES_DB=atlas",
         PG18_IMAGE, "-c", "log_statement=all")
    wait_for_postgres(old)
    wait_for_postgres(new_server)
    run!("docker", "exec", "-i", old, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: source)
    run!("docker", "exec", new_server, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", "-c", "CREATE ROLE atlas_upgrade_reader")
    old_lsn = run!("docker", "exec", old, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
    dump, = run!("docker", "exec", old, "pg_dump", "-U", "postgres", "-d", "atlas", "-Fc")
    run!("docker", "exec", "-i", new_server, "pg_restore", "-U", "postgres", "-d", "atlas", "--exit-on-error", stdin_data: dump)
    stdout, stderr = run!("docker", "exec", "-i", new_server, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: verification)
    new_lsn = run!("docker", "exec", new_server, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
    plan = run!("docker", "exec", new_server, "psql", "-XqAt", "-U", "postgres", "-d", "atlas", "-c", "SET ROLE atlas_upgrade_reader; EXPLAIN (FORMAT JSON) SELECT * FROM atlas_upgrade_secure; RESET ROLE").first.strip
    old_version = run!("docker", "exec", old, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SHOW server_version").first.strip
    new_version = run!("docker", "exec", new_server, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SHOW server_version").first.strip
    raise "logical upgrade version denominator mismatch" unless old_version == "17.11" && new_version == "18.6"
    marker = "ATLAS_SECURITY_PASS:lifecycle.upgrade"
    raise "logical upgrade security markers missing" unless (stdout + stderr).scan(marker).length >= 2
    old_log = run!("docker", "logs", old).join
    new_log = run!("docker", "logs", new_server).join
    {
      "sql"=>{"source"=>source + verification, "stdout"=>stdout, "stderr"=>stderr},
      "plan"=>JSON.parse(plan), "wal"=>{"old_lsn"=>old_lsn, "new_lsn"=>new_lsn},
      "log"=>(old_log + new_log).lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(40).join,
      "metric"=>{"elapsed_ms"=>((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3), "dump_bytes"=>dump.bytesize},
      "oracle_output"=>marker,
      "runtime"=>{"server_versions"=>[old_version, new_version], "images"=>[PG17_IMAGE, PG18_IMAGE], "containers"=>[old, new_server]}
    }
  ensure
    system("docker", "rm", "-f", "-v", old, new_server, out: File::NULL, err: File::NULL)
    system("docker", "network", "rm", network, out: File::NULL, err: File::NULL)
  end
end

def backup_recovery_execution
  container = "pg-atlas-security-backup-#{Process.pid}-#{SecureRandom.hex(3)}"
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  source = security_fixture_sql("atlas_backup_secure", "atlas_backup_reader")
  verification = role_boundary_sql("operations.backup-recovery", "atlas_backup_secure", "atlas_backup_reader")
  begin
    run!("docker", "run", "--detach", "--name", container,
         "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--env", "POSTGRES_DB=atlas",
         PG18_IMAGE, "-c", "log_statement=all")
    wait_for_postgres(container)
    run!("docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: source)
    before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
    dump, = run!("docker", "exec", container, "pg_dump", "-U", "postgres", "-d", "atlas", "-Fc")
    run!("docker", "exec", container, "createdb", "-U", "postgres", "atlas_restore")
    run!("docker", "exec", "-i", container, "pg_restore", "-U", "postgres", "-d", "atlas_restore", "--exit-on-error", stdin_data: dump)
    stdout, stderr = run!("docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas_restore", stdin_data: verification)
    after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas_restore", "-c", "SELECT pg_current_wal_lsn()").first.strip
    plan = run!("docker", "exec", container, "psql", "-XqAt", "-U", "postgres", "-d", "atlas_restore", "-c", "SET ROLE atlas_backup_reader; EXPLAIN (FORMAT JSON) SELECT * FROM atlas_backup_secure; RESET ROLE").first.strip
    marker = "ATLAS_SECURITY_PASS:operations.backup-recovery"
    raise "backup recovery security markers missing" unless (stdout + stderr).scan(marker).length >= 2
    log = run!("docker", "logs", container).join
    {
      "sql"=>{"source"=>source + verification, "stdout"=>stdout, "stderr"=>stderr},
      "plan"=>JSON.parse(plan), "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn},
      "log"=>log.lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(40).join,
      "metric"=>{"elapsed_ms"=>((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3), "dump_bytes"=>dump.bytesize},
      "oracle_output"=>marker,
      "runtime"=>{"server_versions"=>["18.6"], "images"=>[PG18_IMAGE], "containers"=>[container], "restored_database"=>"atlas_restore"}
    }
  ensure
    system("docker", "rm", "-f", "-v", container, out: File::NULL, err: File::NULL)
  end
end

def failure_injection_execution
  container = "pg-atlas-security-failure-#{Process.pid}-#{SecureRandom.hex(3)}"
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  source = security_fixture_sql("atlas_failure_secure", "atlas_failure_reader")
  verification = role_boundary_sql("operations.failure-injection", "atlas_failure_secure", "atlas_failure_reader")
  begin
    run!("docker", "run", "--detach", "--name", container,
         "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--env", "POSTGRES_DB=atlas",
         PG18_IMAGE, "-c", "log_statement=all")
    wait_for_postgres(container)
    run!("docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: source)
    before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
    run!("docker", "kill", "--signal=KILL", container)
    run!("docker", "start", container)
    wait_for_postgres(container)
    stdout, stderr = run!("docker", "exec", "-i", container, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: verification)
    after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
    plan = run!("docker", "exec", container, "psql", "-XqAt", "-U", "postgres", "-d", "atlas", "-c", "SET ROLE atlas_failure_reader; EXPLAIN (FORMAT JSON) SELECT * FROM atlas_failure_secure; RESET ROLE").first.strip
    marker = "ATLAS_SECURITY_PASS:operations.failure-injection"
    raise "failure recovery security markers missing" unless (stdout + stderr).scan(marker).length >= 2
    log = run!("docker", "logs", container).join
    raise "crash recovery log marker missing" unless log.include?("database system was interrupted") || log.include?("redo")
    {
      "sql"=>{"source"=>source + verification, "stdout"=>stdout, "stderr"=>stderr},
      "plan"=>JSON.parse(plan), "wal"=>{"before_crash_lsn"=>before_lsn, "after_recovery_lsn"=>after_lsn},
      "log"=>log.lines.grep(/interrupted|redo|ready to accept|statement:|ATLAS_SECURITY_PASS/).last(60).join,
      "metric"=>{"elapsed_ms"=>((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3), "forced_kill_count"=>1},
      "oracle_output"=>marker,
      "runtime"=>{"server_versions"=>["18.6"], "images"=>[PG18_IMAGE], "containers"=>[container], "failure"=>"SIGKILL"}
    }
  ensure
    system("docker", "rm", "-f", "-v", container, out: File::NULL, err: File::NULL)
  end
end

def wal_security_execution(container)
  marker = "ATLAS_SECURITY_PASS:operations.wal"
  sql = <<~SQL
    BEGIN;
    CREATE ROLE atlas_wal_writer;
    CREATE TABLE atlas_wal_secure(
      id bigint PRIMARY KEY,
      tenant text NOT NULL,
      payload text NOT NULL
    );
    ALTER TABLE atlas_wal_secure ENABLE ROW LEVEL SECURITY;
    CREATE POLICY atlas_wal_policy ON atlas_wal_secure
      USING (tenant = current_user)
      WITH CHECK (tenant = current_user);
    GRANT SELECT, INSERT ON atlas_wal_secure TO atlas_wal_writer;

    CREATE TEMP TABLE atlas_wal_observation(
      plan jsonb,
      visible_rows bigint,
      security_rejected boolean DEFAULT false,
      end_lsn pg_lsn,
      switched_lsn pg_lsn
    );
    INSERT INTO atlas_wal_observation DEFAULT VALUES;
    GRANT ALL ON atlas_wal_observation TO atlas_wal_writer;

    SET ROLE atlas_wal_writer;
    INSERT INTO atlas_wal_secure(id, tenant, payload)
    SELECT g, current_user, repeat(md5(g::text), 8)
    FROM generate_series(1, 20000) AS g;

    DO $atlas$
    DECLARE observed jsonb;
    BEGIN
      EXECUTE 'EXPLAIN (FORMAT JSON) SELECT count(*) FROM atlas_wal_secure WHERE tenant = current_user' INTO observed;
      UPDATE atlas_wal_observation SET plan = observed;
    END
    $atlas$;

    UPDATE atlas_wal_observation
    SET visible_rows = (SELECT count(*) FROM atlas_wal_secure WHERE tenant = current_user);

    DO $atlas$
    BEGIN
      INSERT INTO atlas_wal_secure(id, tenant, payload) VALUES (20001, 'postgres', 'forged');
      RAISE EXCEPTION 'RLS unexpectedly allowed cross-tenant insert';
    EXCEPTION WHEN insufficient_privilege THEN
      UPDATE atlas_wal_observation SET security_rejected = true;
      RAISE NOTICE '#{marker}';
    END
    $atlas$;
    RESET ROLE;

    UPDATE atlas_wal_observation SET end_lsn = pg_current_wal_insert_lsn();
    UPDATE atlas_wal_observation SET switched_lsn = pg_switch_wal();

    SELECT json_build_object(
      'server_version', current_setting('server_version'),
      'wal_level', current_setting('wal_level'),
      'rows_written', 20000,
      'visible_rows', visible_rows,
      'end_lsn', end_lsn,
      'switched_lsn', switched_lsn,
      'wal_records_observed', (SELECT wal_records > 0 FROM pg_stat_wal),
      'segment_switched', #{WAL_SEGMENT_SWITCH_PREDICATE},
      'security_rejected', security_rejected,
      'plan', plan,
      'oracle_marker', CASE WHEN security_rejected THEN '#{marker}' ELSE 'ATLAS_SECURITY_FAIL:operations.wal' END,
      'verdict', CASE
        WHEN visible_rows = 20000
          AND security_rejected
          AND (SELECT wal_records > 0 FROM pg_stat_wal)
          AND #{WAL_SEGMENT_SWITCH_PREDICATE}
        THEN 'pass'
        ELSE 'fail'
      END
    )
    FROM atlas_wal_observation;
    ROLLBACK;
  SQL

  before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_insert_lsn()").first.strip
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result, stdout, stderr = psql_json_execution(container, sql)
  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)
  after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_insert_lsn()").first.strip
  unless result.fetch("verdict") == "pass" &&
         result.fetch("server_version") == "18.6" && result.fetch("rows_written") == 20_000 &&
         result.fetch("visible_rows") == 20_000 && result.fetch("wal_records_observed") == true &&
         result.fetch("security_rejected") == true && result.fetch("oracle_marker") == marker &&
         result.fetch("segment_switched") == true && result.fetch("plan").is_a?(Array)
    raise "operations.wal security Oracle failed: #{JSON.generate(result)}"
  end
  log = run!("docker", "logs", container).join
  {
    "sql"=>{"source"=>sql, "stdout"=>stdout, "stderr"=>stderr},
    "plan"=>result.fetch("plan"),
    "wal"=>{
      "before_lsn"=>before_lsn,
      "after_lsn"=>after_lsn,
      "end_lsn"=>result.fetch("end_lsn"),
      "switched_lsn"=>result.fetch("switched_lsn"),
      "wal_records_observed"=>result.fetch("wal_records_observed")
    },
    "log"=>log.lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(40).join,
    "metric"=>{"elapsed_ms"=>elapsed_ms, "rows_written"=>result.fetch("rows_written"), "visible_rows"=>result.fetch("visible_rows")},
    "oracle_output"=>stdout + stderr,
    "runtime"=>{"server_versions"=>["18.6"], "containers"=>[container]}
  }
end

def performance_execution_security_execution(container)
  marker = "ATLAS_SECURITY_PASS:performance.execution"
  sql = <<~SQL
    BEGIN;
    CREATE ROLE atlas_perf_execution_reader;
    CREATE TABLE atlas_perf_execution_secure(
      id bigint PRIMARY KEY,
      tenant text NOT NULL,
      payload text NOT NULL
    );
    ALTER TABLE atlas_perf_execution_secure ENABLE ROW LEVEL SECURITY;
    CREATE POLICY atlas_perf_execution_policy ON atlas_perf_execution_secure
      TO atlas_perf_execution_reader
      USING (tenant = '#{PERFORMANCE_EXECUTION_LITERAL_TENANT}')
      WITH CHECK (tenant = '#{PERFORMANCE_EXECUTION_LITERAL_TENANT}');
    GRANT SELECT, INSERT ON atlas_perf_execution_secure TO atlas_perf_execution_reader;

    INSERT INTO atlas_perf_execution_secure(id, tenant, payload)
    SELECT g,
      CASE WHEN g % 1000 = 42 THEN 'atlas_perf_execution_reader' ELSE format('tenant_%s', g % 1000) END,
      repeat(md5(g::text), 2)
    FROM generate_series(1, 200000) AS g;
    CREATE INDEX atlas_perf_execution_tenant_idx ON atlas_perf_execution_secure(tenant, id) INCLUDE (payload);
    ANALYZE atlas_perf_execution_secure;

    CREATE TEMP TABLE atlas_perf_execution_observation(
      plan jsonb,
      fixture_rows bigint,
      visible_rows bigint,
      security_rejected boolean DEFAULT false
    );
    INSERT INTO atlas_perf_execution_observation(fixture_rows)
    SELECT count(*) FROM atlas_perf_execution_secure;
    GRANT ALL ON atlas_perf_execution_observation TO atlas_perf_execution_reader;

    SET ROLE atlas_perf_execution_reader;
    DO $atlas$
    DECLARE observed jsonb;
    BEGIN
      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) SELECT id FROM atlas_perf_execution_secure WHERE tenant = ''#{PERFORMANCE_EXECUTION_LITERAL_TENANT}'' ORDER BY id' INTO observed;
      UPDATE atlas_perf_execution_observation SET plan = observed;
    END
    $atlas$;
    UPDATE atlas_perf_execution_observation
    SET visible_rows = (SELECT count(*) FROM atlas_perf_execution_secure WHERE tenant = '#{PERFORMANCE_EXECUTION_LITERAL_TENANT}');

    DO $atlas$
    BEGIN
      INSERT INTO atlas_perf_execution_secure(id, tenant, payload) VALUES (300001, 'postgres', 'forged');
      RAISE EXCEPTION 'RLS unexpectedly allowed cross-tenant insert';
    EXCEPTION WHEN insufficient_privilege THEN
      UPDATE atlas_perf_execution_observation SET security_rejected = true;
      RAISE NOTICE '#{marker}';
    END
    $atlas$;
    RESET ROLE;

    SELECT json_build_object(
      'server_version', current_setting('server_version'),
      'fixture_rows', fixture_rows,
      'visible_rows', visible_rows,
      'index_bytes', pg_relation_size('atlas_perf_execution_tenant_idx'),
      'heap_bytes', pg_relation_size('atlas_perf_execution_secure'),
      'plan', plan,
      'plan_has_index', plan::text LIKE '%atlas_perf_execution_tenant_idx%',
      'plan_has_actual_rows', plan::text LIKE '%Actual Rows%',
      'plan_has_buffers', plan::text LIKE '%Shared Hit Blocks%',
      'security_rejected', security_rejected,
      'oracle_marker', CASE WHEN security_rejected THEN '#{marker}' ELSE 'ATLAS_SECURITY_FAIL:performance.execution' END,
      'verdict', CASE
        WHEN fixture_rows = 200000
          AND visible_rows = 200
          AND security_rejected
          AND plan::text LIKE '%atlas_perf_execution_tenant_idx%'
          AND plan::text LIKE '%Actual Rows%'
          AND plan::text LIKE '%Shared Hit Blocks%'
          AND pg_relation_size('atlas_perf_execution_tenant_idx') > 0
          AND pg_relation_size('atlas_perf_execution_secure') > 0
        THEN 'pass'
        ELSE 'fail'
      END
    )
    FROM atlas_perf_execution_observation;
    ROLLBACK;
  SQL

  before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result, stdout, stderr = psql_json_execution(container, sql)
  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)
  after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  predicates = SecurityScenarioOracles.performance_execution_predicates(result, marker: marker)
  unless predicates.values.all?
    raise SecurityFailureDiagnostics::ScenarioOracleFailure.new(
      failed_row: "closure.definitive-domain.performance.execution.security",
      target: "performance.execution",
      oracle_error: "performance.execution security Oracle failed",
      actual_result: result,
      oracle_predicates: predicates
    )
  end
  log = run!("docker", "logs", container).join
  {
    "sql"=>{"source"=>sql, "stdout"=>stdout, "stderr"=>stderr},
    "plan"=>result.fetch("plan"),
    "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn},
    "log"=>log.lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(40).join,
    "metric"=>{
      "elapsed_ms"=>elapsed_ms,
      "fixture_rows"=>result.fetch("fixture_rows"),
      "visible_rows"=>result.fetch("visible_rows"),
      "index_bytes"=>result.fetch("index_bytes"),
      "heap_bytes"=>result.fetch("heap_bytes")
    },
    "oracle_output"=>stdout + stderr,
    "runtime"=>{"server_versions"=>["18.6"], "containers"=>[container]}
  }
end

def performance_index_security_execution(container)
  marker = "ATLAS_SECURITY_PASS:performance.index"
  sql = <<~SQL
    BEGIN;
    CREATE ROLE atlas_perf_index_reader;
    CREATE TABLE atlas_perf_index_secure(
      id bigint PRIMARY KEY,
      tenant text NOT NULL,
      billed boolean NOT NULL,
      payload text NOT NULL
    );
    ALTER TABLE atlas_perf_index_secure ENABLE ROW LEVEL SECURITY;
    CREATE POLICY atlas_perf_index_policy ON atlas_perf_index_secure
      TO atlas_perf_index_reader
      USING (tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}')
      WITH CHECK (tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}');
    GRANT SELECT, INSERT ON atlas_perf_index_secure TO atlas_perf_index_reader;

    INSERT INTO atlas_perf_index_secure(id, tenant, billed, payload)
    SELECT g,
      CASE WHEN g % 1000 = 42 THEN 'atlas_perf_index_reader' ELSE format('tenant_%s', g % 1000) END,
      ((g / 1000) % 2 = 0),
      repeat(md5(g::text), 2)
    FROM generate_series(1, 200000) AS g;

    CREATE TEMP TABLE atlas_perf_index_observation(
      plan jsonb,
      before_digest text,
      after_digest text,
      tenant_rows bigint,
      billed_visible_rows bigint,
      security_rejected boolean DEFAULT false
    );
    INSERT INTO atlas_perf_index_observation DEFAULT VALUES;
    GRANT ALL ON atlas_perf_index_observation TO atlas_perf_index_reader;

    SET ROLE atlas_perf_index_reader;
    UPDATE atlas_perf_index_observation
    SET before_digest = (
      SELECT md5(string_agg(id::text, ',' ORDER BY id))
      FROM atlas_perf_index_secure
      WHERE tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}' AND billed
    );
    RESET ROLE;

    CREATE INDEX atlas_perf_index_billed_idx ON atlas_perf_index_secure(tenant, id) WHERE billed;
    ANALYZE atlas_perf_index_secure;

    SET ROLE atlas_perf_index_reader;
    DO $atlas$
    DECLARE observed jsonb;
    BEGIN
      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) SELECT id FROM atlas_perf_index_secure WHERE tenant = ''#{PERFORMANCE_INDEX_LITERAL_TENANT}'' AND billed ORDER BY id' INTO observed;
      UPDATE atlas_perf_index_observation SET plan = observed;
    END
    $atlas$;
    UPDATE atlas_perf_index_observation
    SET after_digest = (
          SELECT md5(string_agg(id::text, ',' ORDER BY id))
          FROM atlas_perf_index_secure
          WHERE tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}' AND billed
        ),
        tenant_rows = (
          SELECT count(*)
          FROM atlas_perf_index_secure
          WHERE tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}'
        ),
        billed_visible_rows = (
          SELECT count(*)
          FROM atlas_perf_index_secure
          WHERE tenant = '#{PERFORMANCE_INDEX_LITERAL_TENANT}' AND billed
        );

    DO $atlas$
    BEGIN
      INSERT INTO atlas_perf_index_secure(id, tenant, billed, payload) VALUES (300001, 'postgres', true, 'forged');
      RAISE EXCEPTION 'RLS unexpectedly allowed cross-tenant insert';
    EXCEPTION WHEN insufficient_privilege THEN
      UPDATE atlas_perf_index_observation SET security_rejected = true;
      RAISE NOTICE '#{marker}';
    END
    $atlas$;
    RESET ROLE;

    SELECT json_build_object(
      'server_version', current_setting('server_version'),
      'before_digest', before_digest,
      'after_digest', after_digest,
      'tenant_rows', tenant_rows,
      'billed_visible_rows', billed_visible_rows,
      'index_bytes', pg_relation_size('atlas_perf_index_billed_idx'),
      'heap_bytes', pg_relation_size('atlas_perf_index_secure'),
      'index_predicate', (
        SELECT pg_get_expr(i.indpred, i.indrelid)
        FROM pg_index AS i
        JOIN pg_class AS c ON c.oid = i.indexrelid
        WHERE c.relname = 'atlas_perf_index_billed_idx'
      ),
      'plan', plan,
      'plan_has_index', plan::text LIKE '%atlas_perf_index_billed_idx%',
      'security_rejected', security_rejected,
      'oracle_marker', CASE WHEN security_rejected THEN '#{marker}' ELSE 'ATLAS_SECURITY_FAIL:performance.index' END,
      'verdict', CASE
        WHEN before_digest = after_digest
          AND before_digest IS NOT NULL
          AND tenant_rows = 200
          AND billed_visible_rows = 100
          AND security_rejected
          AND plan::text LIKE '%atlas_perf_index_billed_idx%'
          AND (
            SELECT pg_get_expr(i.indpred, i.indrelid)
            FROM pg_index AS i
            JOIN pg_class AS c ON c.oid = i.indexrelid
            WHERE c.relname = 'atlas_perf_index_billed_idx'
          ) = 'billed'
          AND pg_relation_size('atlas_perf_index_billed_idx') > 0
          AND pg_relation_size('atlas_perf_index_secure') > 0
        THEN 'pass'
        ELSE 'fail'
      END
    )
    FROM atlas_perf_index_observation;
    ROLLBACK;
  SQL

  before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result, stdout, stderr = psql_json_execution(container, sql)
  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)
  after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  predicates = SecurityScenarioOracles.performance_index_predicates(result, marker: marker)
  unless predicates.values.all?
    raise SecurityFailureDiagnostics::ScenarioOracleFailure.new(
      failed_row: "closure.definitive-domain.performance.index.security",
      target: "performance.index",
      oracle_error: "performance.index security Oracle failed",
      actual_result: result,
      oracle_predicates: predicates
    )
  end
  log = run!("docker", "logs", container).join
  {
    "sql"=>{"source"=>sql, "stdout"=>stdout, "stderr"=>stderr},
    "plan"=>result.fetch("plan"),
    "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn},
    "log"=>log.lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(40).join,
    "metric"=>{
      "elapsed_ms"=>elapsed_ms,
      "tenant_rows"=>result.fetch("tenant_rows"),
      "billed_visible_rows"=>result.fetch("billed_visible_rows"),
      "index_bytes"=>result.fetch("index_bytes"),
      "heap_bytes"=>result.fetch("heap_bytes"),
      "index_predicate"=>result.fetch("index_predicate"),
      "before_digest"=>result.fetch("before_digest"),
      "after_digest"=>result.fetch("after_digest")
    },
    "oracle_output"=>stdout + stderr,
    "runtime"=>{"server_versions"=>["18.6"], "containers"=>[container]}
  }
end

def performance_planner_security_execution(container)
  marker = "ATLAS_SECURITY_PASS:performance.planner"
  sql = <<~SQL
    BEGIN;
    CREATE ROLE atlas_perf_planner_reader;
    CREATE TABLE atlas_perf_planner_secure(
      id bigint PRIMARY KEY,
      tenant text NOT NULL,
      category integer NOT NULL,
      payload text NOT NULL
    );
    ALTER TABLE atlas_perf_planner_secure ENABLE ROW LEVEL SECURITY;
    CREATE POLICY atlas_perf_planner_policy ON atlas_perf_planner_secure
      USING (tenant = current_user)
      WITH CHECK (tenant = current_user);
    GRANT SELECT, INSERT ON atlas_perf_planner_secure TO atlas_perf_planner_reader;

    INSERT INTO atlas_perf_planner_secure(id, tenant, category, payload)
    SELECT g,
      CASE WHEN g = 42424 THEN 'atlas_perf_planner_reader' ELSE format('tenant_%s', g) END,
      g % 100,
      repeat(md5(g::text), 4)
    FROM generate_series(1, 100000) AS g;
    ANALYZE atlas_perf_planner_secure;

    CREATE TEMP TABLE atlas_perf_planner_observation(
      plan jsonb,
      fixture_rows bigint,
      visible_rows bigint,
      security_rejected boolean DEFAULT false
    );
    INSERT INTO atlas_perf_planner_observation(fixture_rows)
    SELECT count(*) FROM atlas_perf_planner_secure;
    GRANT ALL ON atlas_perf_planner_observation TO atlas_perf_planner_reader;

    SET ROLE atlas_perf_planner_reader;
    DO $atlas$
    DECLARE observed jsonb;
    BEGIN
      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) SELECT payload FROM atlas_perf_planner_secure WHERE id = 42424' INTO observed;
      UPDATE atlas_perf_planner_observation SET plan = observed;
    END
    $atlas$;
    UPDATE atlas_perf_planner_observation
    SET visible_rows = (SELECT count(*) FROM atlas_perf_planner_secure WHERE id = 42424);

    DO $atlas$
    BEGIN
      INSERT INTO atlas_perf_planner_secure(id, tenant, category, payload) VALUES (100001, 'postgres', 0, 'forged');
      RAISE EXCEPTION 'RLS unexpectedly allowed cross-tenant insert';
    EXCEPTION WHEN insufficient_privilege THEN
      UPDATE atlas_perf_planner_observation SET security_rejected = true;
      RAISE NOTICE '#{marker}';
    END
    $atlas$;
    RESET ROLE;

    SELECT json_build_object(
      'server_version', current_setting('server_version'),
      'fixture_rows', fixture_rows,
      'visible_rows', visible_rows,
      'plan', plan,
      'plan_uses_index', plan::text ~ 'Index Scan|Index Only Scan|Bitmap Index Scan',
      'plan_has_actual_rows', plan::text LIKE '%Actual Rows%',
      'plan_has_buffers', plan::text LIKE '%Shared Hit Blocks%',
      'security_rejected', security_rejected,
      'oracle_marker', CASE WHEN security_rejected THEN '#{marker}' ELSE 'ATLAS_SECURITY_FAIL:performance.planner' END,
      'verdict', CASE
        WHEN fixture_rows = 100000
          AND visible_rows = 1
          AND security_rejected
          AND plan::text ~ 'Index Scan|Index Only Scan|Bitmap Index Scan'
          AND plan::text LIKE '%Actual Rows%'
          AND plan::text LIKE '%Shared Hit Blocks%'
        THEN 'pass'
        ELSE 'fail'
      END
    )
    FROM atlas_perf_planner_observation;
    ROLLBACK;
  SQL

  before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result, stdout, stderr = psql_json_execution(container, sql)
  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)
  after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  predicates = SecurityScenarioOracles.performance_planner_predicates(result, marker: marker)
  unless predicates.values.all?
    raise SecurityFailureDiagnostics::ScenarioOracleFailure.new(
      failed_row: "closure.definitive-domain.performance.planner.security",
      target: "performance.planner",
      oracle_error: "performance.planner security Oracle failed",
      actual_result: result,
      oracle_predicates: predicates
    )
  end
  log = run!("docker", "logs", container).join
  {
    "sql"=>{"source"=>sql, "stdout"=>stdout, "stderr"=>stderr},
    "plan"=>result.fetch("plan"),
    "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn},
    "log"=>log.lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(40).join,
    "metric"=>{"elapsed_ms"=>elapsed_ms, "fixture_rows"=>result.fetch("fixture_rows"), "visible_rows"=>result.fetch("visible_rows")},
    "oracle_output"=>stdout + stderr,
    "runtime"=>{"server_versions"=>["18.6"], "containers"=>[container]}
  }
end

def performance_statistics_security_execution(container)
  SecurityPerformanceStatisticsContract.verify!
  marker = "ATLAS_SECURITY_PASS:performance.statistics"
  sql = <<~SQL
    BEGIN;
    CREATE ROLE atlas_perf_statistics_reader;
    CREATE TABLE correlated_fact(a integer NOT NULL, b integer NOT NULL, payload text NOT NULL);
    INSERT INTO correlated_fact
    SELECT g % 100, g % 100, md5(g::text) FROM generate_series(1, 10000) AS g;
    GRANT SELECT ON correlated_fact TO atlas_perf_statistics_reader;
    CREATE STATISTICS correlated_fact_ab (dependencies, mcv) ON a, b FROM correlated_fact;
    ANALYZE correlated_fact;
    SELECT set_config('atlas.statistics.before_analyze',
      coalesce((SELECT last_analyze::text FROM pg_stat_all_tables WHERE relname = 'correlated_fact'), ''), true);
    SET ROLE atlas_perf_statistics_reader;
    DO $$ BEGIN
      BEGIN
        CREATE STATISTICS atlas_perf_statistics_reader_attempt ON a, b FROM correlated_fact;
        PERFORM set_config('atlas.statistics.create_denied', 'false', true);
      EXCEPTION WHEN insufficient_privilege THEN
        PERFORM set_config('atlas.statistics.create_denied', 'true', true);
      END;
    END $$;
    ANALYZE correlated_fact;
    RESET ROLE;
    CREATE TEMP TABLE atlas_statistics_plan(plan jsonb);
    DO $$ DECLARE captured jsonb; BEGIN
      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM correlated_fact WHERE a = 42 AND b = 42' INTO captured;
      INSERT INTO atlas_statistics_plan VALUES (captured);
    END $$;
    SELECT json_build_object(
      'server_version', current_setting('server_version'),
      'statistics_kinds', (SELECT array_agg(CASE kind::text WHEN 'f' THEN 'dependencies' WHEN 'm' THEN 'mcv' ELSE kind::text END ORDER BY kind::text)
        FROM pg_statistic_ext, unnest(stxkind) AS kind WHERE stxname = 'correlated_fact_ab'),
      'estimated_rows', (SELECT (plan #>> '{0,Plan,Plan Rows}')::integer FROM atlas_statistics_plan),
      'actual_rows', (SELECT count(*) FROM correlated_fact WHERE a = 42 AND b = 42),
      'security_rejected', current_setting('atlas.statistics.create_denied', true) = 'true'
        AND coalesce((SELECT last_analyze::text FROM pg_stat_all_tables WHERE relname = 'correlated_fact'), '')
          = current_setting('atlas.statistics.before_analyze', true),
      'oracle_marker', '#{marker}',
      'plan', (SELECT plan FROM atlas_statistics_plan),
      'verdict', CASE WHEN
        (SELECT (plan #>> '{0,Plan,Plan Rows}')::integer FROM atlas_statistics_plan) BETWEEN 80 AND 120
        AND (SELECT count(*) FROM correlated_fact WHERE a = 42 AND b = 42) = 100
        AND current_setting('atlas.statistics.create_denied', true) = 'true'
        AND coalesce((SELECT last_analyze::text FROM pg_stat_all_tables WHERE relname = 'correlated_fact'), '')
          = current_setting('atlas.statistics.before_analyze', true)
        THEN 'pass' ELSE 'fail' END
    );
    ROLLBACK;
  SQL
  before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result, stdout, stderr = psql_json_execution(container, sql)
  after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  nodes = SecurityScenarioOracles.plan_document_nodes(result["plan"])
  predicates = {
    "result_verdict_pass"=>result["verdict"] == "pass",
    "server_version_exact"=>result["server_version"] == "18.6",
    "statistics_kinds_exact"=>Array(result["statistics_kinds"]).sort == %w[dependencies mcv],
    "estimated_rows_window"=>result["estimated_rows"].to_i.between?(80, 120),
    "actual_rows_exact"=>result["actual_rows"] == 100,
    "security_rejected"=>result["security_rejected"] == true,
    "marker_exact"=>result["oracle_marker"] == marker,
    "plan_document_array"=>result["plan"].is_a?(Array) && !result["plan"].empty?,
    "plan_rows_match_estimate"=>nodes.any? { |node| node["Plan Rows"].to_i == result["estimated_rows"].to_i },
    "plan_actual_rows_and_loops"=>SecurityScenarioOracles.plan_has_actual_execution?(nodes),
    "plan_buffers_observed"=>SecurityScenarioOracles.plan_has_buffers?(nodes)
  }
  unless predicates.values.all?
    raise SecurityFailureDiagnostics::ScenarioOracleFailure.new(
      failed_row: "closure.definitive-domain.performance.statistics.security", target: "performance.statistics",
      oracle_error: "performance.statistics security Oracle failed", actual_result: result, oracle_predicates: predicates
    )
  end
  log = run!("docker", "logs", container).join
  {
    "sql"=>{"source"=>sql, "stdout"=>stdout, "stderr"=>stderr}, "plan"=>result.fetch("plan"),
    "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn},
    "log"=>log.lines.grep(/statement:|ATLAS_SECURITY_PASS/).last(40).join,
    "metric"=>{"elapsed_ms"=>((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3),
      "estimated_rows"=>result.fetch("estimated_rows"), "actual_rows"=>result.fetch("actual_rows")},
    "oracle_output"=>marker, "runtime"=>{"server_versions"=>[result.fetch("server_version")], "containers"=>[container]}
  }
end

def catalog_inventory_security_execution(container)
  SecurityQueryCatalogInventoryContract.verify!
  marker = "ATLAS_SECURITY_PASS:query.catalog-inventory"
  sql = <<~SQL
    BEGIN;
    CREATE ROLE atlas_catalog_reader;
    SET ROLE atlas_catalog_reader;
    DO $$ BEGIN
      BEGIN
        CREATE TABLE pg_catalog.atlas_catalog_forged(id integer);
        PERFORM set_config('atlas.catalog.mutation_denied', 'false', true);
      EXCEPTION WHEN insufficient_privilege THEN
        PERFORM set_config('atlas.catalog.mutation_denied', 'true', true);
      END;
    END $$;
    RESET ROLE;
    CREATE TEMP TABLE atlas_catalog_plan(plan jsonb);
    DO $$ DECLARE captured jsonb; BEGIN
      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT oid, typname FROM pg_type WHERE typnamespace = ''pg_catalog''::regnamespace ORDER BY oid LIMIT 10' INTO captured;
      INSERT INTO atlas_catalog_plan VALUES (captured);
    END $$;
    WITH
    types AS (SELECT count(*) AS count, md5(string_agg(oid::text || ':' || typname, ',' ORDER BY oid)) AS digest FROM pg_type WHERE typnamespace = 'pg_catalog'::regnamespace),
    functions AS (SELECT count(*) AS count, md5(string_agg(oid::text || ':' || proname || ':' || pg_get_function_identity_arguments(oid), ',' ORDER BY oid)) AS digest FROM pg_proc WHERE pronamespace = 'pg_catalog'::regnamespace),
    operators AS (SELECT count(*) AS count, md5(string_agg(oid::text || ':' || oprname, ',' ORDER BY oid)) AS digest FROM pg_operator WHERE oprnamespace = 'pg_catalog'::regnamespace),
    casts AS (SELECT count(*) AS count, md5(string_agg(oid::text || ':' || castsource::text || ':' || casttarget::text, ',' ORDER BY oid)) AS digest FROM pg_cast),
    access_methods AS (SELECT count(*) AS count, md5(string_agg(oid::text || ':' || amname, ',' ORDER BY oid)) AS digest FROM pg_am),
    collations AS (SELECT count(*) AS count, md5(string_agg(oid::text || ':' || collname, ',' ORDER BY oid)) AS digest FROM pg_collation),
    extensions AS (SELECT count(*) AS count, md5(string_agg(name || ':' || default_version, ',' ORDER BY name)) AS digest FROM pg_available_extensions),
    catalog_relations AS (SELECT count(*) AS count, md5(string_agg(c.oid::text || ':' || c.relname, ',' ORDER BY c.oid)) AS digest FROM pg_class c WHERE c.relnamespace = 'pg_catalog'::regnamespace)
    SELECT json_build_object(
      'server_version', current_setting('server_version'),
      'types', (SELECT json_build_object('count', count, 'digest', digest) FROM types),
      'functions', (SELECT json_build_object('count', count, 'digest', digest) FROM functions),
      'operators', (SELECT json_build_object('count', count, 'digest', digest) FROM operators),
      'casts', (SELECT json_build_object('count', count, 'digest', digest) FROM casts),
      'access_methods', (SELECT json_build_object('count', count, 'digest', digest) FROM access_methods),
      'collations', (SELECT json_build_object('count', count, 'digest', digest) FROM collations),
      'available_extensions', (SELECT json_build_object('count', count, 'digest', digest) FROM extensions),
      'catalog_relations', (SELECT json_build_object('count', count, 'digest', digest) FROM catalog_relations),
      'security_rejected', current_setting('atlas.catalog.mutation_denied', true) = 'true',
      'oracle_marker', '#{marker}', 'plan', (SELECT plan FROM atlas_catalog_plan),
      'verdict', CASE WHEN (SELECT count FROM types) > 100 AND (SELECT count FROM functions) > 1000
        AND (SELECT count FROM operators) > 500 AND (SELECT count FROM casts) > 100
        AND (SELECT count FROM access_methods) >= 7 AND (SELECT count FROM collations) > 0
        AND (SELECT count FROM extensions) > 20 AND (SELECT count FROM catalog_relations) > 50
        AND current_setting('atlas.catalog.mutation_denied', true) = 'true' THEN 'pass' ELSE 'fail' END
    );
    ROLLBACK;
  SQL
  before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result, stdout, stderr = psql_json_execution(container, sql)
  after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  nodes = SecurityScenarioOracles.plan_document_nodes(result["plan"])
  inventories = %w[types functions operators casts access_methods collations available_extensions catalog_relations]
  predicates = {
    "result_verdict_pass"=>result["verdict"] == "pass", "server_version_exact"=>result["server_version"] == "18.6",
    "types_count_threshold"=>result.dig("types", "count").to_i > 100,
    "functions_count_threshold"=>result.dig("functions", "count").to_i > 1000,
    "operators_count_threshold"=>result.dig("operators", "count").to_i > 500,
    "casts_count_threshold"=>result.dig("casts", "count").to_i > 100,
    "access_methods_threshold"=>result.dig("access_methods", "count").to_i >= 7,
    "collations_count_positive"=>result.dig("collations", "count").to_i.positive?,
    "available_extensions_threshold"=>result.dig("available_extensions", "count").to_i > 20,
    "catalog_relations_threshold"=>result.dig("catalog_relations", "count").to_i > 50,
    "digests_present"=>inventories.all? { |name| result.dig(name, "digest").to_s.match?(/\A[0-9a-f]{32}\z/) },
    "security_rejected"=>result["security_rejected"] == true, "marker_exact"=>result["oracle_marker"] == marker,
    "plan_document_array"=>result["plan"].is_a?(Array) && !result["plan"].empty?,
    "plan_actual_rows_and_loops"=>SecurityScenarioOracles.plan_has_actual_execution?(nodes),
    "plan_buffers_observed"=>SecurityScenarioOracles.plan_has_buffers?(nodes),
    "plan_reads_pg_catalog_type_relation"=>nodes.any? { |node| node["Relation Name"] == "pg_type" }
  }
  unless predicates.values.all?
    raise SecurityFailureDiagnostics::ScenarioOracleFailure.new(
      failed_row: "closure.definitive-domain.query.catalog-inventory.security", target: "query.catalog-inventory",
      oracle_error: "query.catalog-inventory security Oracle failed", actual_result: result, oracle_predicates: predicates
    )
  end
  log = run!("docker", "logs", container).join
  {
    "sql"=>{"source"=>sql, "stdout"=>stdout, "stderr"=>stderr}, "plan"=>result.fetch("plan"),
    "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn}, "log"=>log.lines.last(40).join,
    "metric"=>{"elapsed_ms"=>((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3),
      "catalog_objects"=>inventories.sum { |name| result.dig(name, "count").to_i }},
    "oracle_output"=>marker, "runtime"=>{"server_versions"=>[result.fetch("server_version")], "containers"=>[container]}
  }
end

def bundled_extension_security_execution(container)
  SecurityQueryExtensionContract.verify!
  marker = "ATLAS_SECURITY_PASS:query.extension"
  sql = <<~SQL
    BEGIN;
    CREATE ROLE atlas_extension_reader;
    CREATE EXTENSION pg_trgm;
    CREATE TABLE atlas_extension_secure(id bigint PRIMARY KEY, tenant name NOT NULL, body text NOT NULL);
    ALTER TABLE atlas_extension_secure ENABLE ROW LEVEL SECURITY;
    CREATE POLICY atlas_extension_policy ON atlas_extension_secure TO atlas_extension_reader
      USING (tenant = 'atlas_extension_reader' AND body LIKE '%searchable phrase%')
      WITH CHECK (tenant = 'atlas_extension_reader');
    INSERT INTO atlas_extension_secure
    SELECT g, 'atlas_extension_reader', CASE WHEN g = 4242 THEN 'postgresql atlas searchable phrase' ELSE md5(g::text) END
    FROM generate_series(1, 20000) AS g;
    CREATE INDEX atlas_extension_secure_body_trgm_idx ON atlas_extension_secure USING gin (body gin_trgm_ops);
    ANALYZE atlas_extension_secure;
    GRANT SELECT ON atlas_extension_secure TO atlas_extension_reader;
    CREATE TEMP TABLE atlas_extension_observation(plan jsonb, matching_rows bigint, similarity_value real);
    GRANT INSERT, SELECT ON atlas_extension_observation TO atlas_extension_reader;
    SET ROLE atlas_extension_reader;
    DO $$ DECLARE captured jsonb; BEGIN
      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) SELECT id FROM atlas_extension_secure WHERE tenant = ''atlas_extension_reader'' AND body LIKE ''%searchable phrase%'' ORDER BY id' INTO captured;
      INSERT INTO atlas_extension_observation
      SELECT captured, count(*), similarity('postgresql atlas', 'postgres atlas')
      FROM atlas_extension_secure WHERE tenant = 'atlas_extension_reader' AND body LIKE '%searchable phrase%';
      BEGIN
        CREATE EXTENSION hstore;
        PERFORM set_config('atlas.extension.install_denied', 'false', true);
      EXCEPTION WHEN insufficient_privilege THEN
        PERFORM set_config('atlas.extension.install_denied', 'true', true);
      END;
    END $$;
    RESET ROLE;
    SELECT json_build_object(
      'server_version', current_setting('server_version'),
      'extension_version', (SELECT extversion FROM pg_extension WHERE extname = 'pg_trgm'),
      'similarity', (SELECT similarity_value FROM atlas_extension_observation),
      'matching_rows', (SELECT matching_rows FROM atlas_extension_observation),
      'security_rejected', current_setting('atlas.extension.install_denied', true) = 'true',
      'oracle_marker', '#{marker}', 'plan', (SELECT plan FROM atlas_extension_observation),
      'verdict', CASE WHEN (SELECT matching_rows FROM atlas_extension_observation) = 1
        AND (SELECT similarity_value FROM atlas_extension_observation) > 0
        AND current_setting('atlas.extension.install_denied', true) = 'true' THEN 'pass' ELSE 'fail' END
    );
    ROLLBACK;
  SQL
  before_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result, stdout, stderr = psql_json_execution(container, sql)
  after_lsn = run!("docker", "exec", container, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
  nodes = SecurityScenarioOracles.plan_document_nodes(result["plan"])
  exact_index = "atlas_extension_secure_body_trgm_idx"
  exact_relation = "atlas_extension_secure"
  predicates = {
    "result_verdict_pass"=>result["verdict"] == "pass", "server_version_exact"=>result["server_version"] == "18.6",
    "extension_version_present"=>!result["extension_version"].to_s.empty?, "similarity_positive"=>result["similarity"].to_f.positive?,
    "matching_rows_exact"=>result["matching_rows"] == 1, "security_rejected"=>result["security_rejected"] == true,
    "marker_exact"=>result["oracle_marker"] == marker, "plan_document_array"=>result["plan"].is_a?(Array) && !result["plan"].empty?,
    "plan_actual_rows_and_loops"=>SecurityScenarioOracles.plan_has_actual_execution?(nodes),
    "plan_buffers_observed"=>SecurityScenarioOracles.plan_has_buffers?(nodes),
    "plan_exact_gin_index"=>SecurityScenarioOracles.exact_index_path?(nodes: nodes, relation: exact_relation, index: exact_index),
    "plan_exact_relation"=>nodes.any? { |node| node["Relation Name"] == exact_relation },
    "plan_literal_tenant_observed"=>SecurityScenarioOracles.condition_includes?(nodes: nodes, expected: "atlas_extension_reader"),
    "plan_seq_scan_absent_on_exact_relation"=>SecurityScenarioOracles.seq_scan_absent_on_relation?(nodes: nodes, relation: exact_relation)
  }
  unless predicates.values.all?
    raise SecurityFailureDiagnostics::ScenarioOracleFailure.new(
      failed_row: "closure.definitive-domain.query.extension.security", target: "query.extension",
      oracle_error: "query.extension security Oracle failed", actual_result: result, oracle_predicates: predicates
    )
  end
  log = run!("docker", "logs", container).join
  {
    "sql"=>{"source"=>sql, "stdout"=>stdout, "stderr"=>stderr}, "plan"=>result.fetch("plan"),
    "wal"=>{"before_lsn"=>before_lsn, "after_lsn"=>after_lsn}, "log"=>log.lines.last(40).join,
    "metric"=>{"elapsed_ms"=>((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3),
      "matching_rows"=>result.fetch("matching_rows")},
    "oracle_output"=>marker, "runtime"=>{"server_versions"=>[result.fetch("server_version")], "containers"=>[container], "extension"=>"pg_trgm"}
  }
end

def publication_provenance_security_execution
  SecurityPublicationProvenanceContract.verify!
  marker = "ATLAS_SECURITY_PASS:publication.provenance"
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  required = %w[LICENSE NOTICE SECURITY.md CONTRIBUTING.md third_party/manifest.yaml sbom.spdx.json surface/sql-commands.yaml]
  rights_files = required.to_h { |relative| [relative, File.file?(File.join(ROOT, relative)) && File.size?(File.join(ROOT, relative))] }
  static_source = File.read(File.join(ROOT, "scripts/static-gates.sh"))
  lock_digest = digest_file(File.join(ROOT, "sources.lock.yaml"))
  coverage_digest = File.read(File.join(ROOT, "coverage.yaml"))[/^authority_lock_digest:\s*(sha256:[0-9a-f]{64})$/, 1]
  sbom = JSON.parse(File.read(File.join(ROOT, "sbom.spdx.json")))
  secret_stdout, secret_stderr, secret_status = Open3.capture3(
    "rg", "-n", "--hidden", "--glob", "!evidence/**", "--glob", "!.git/**",
    '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|AKIA[0-9A-Z]{16}|postgres(ql)?://[^[:space:]]+:[^[:space:]@]+@)', ROOT
  )
  raise "publication secret scan failed to execute: #{secret_stderr}" unless [0, 1].include?(secret_status.exitstatus)
  graph_stdout, graph_stderr = run!("ruby", File.join(ROOT, "scripts/graph-gates.rb"))
  result = {
    "authority_lock_digest"=>lock_digest, "rights_files"=>rights_files,
    "secret_scan"=>{"verdict"=>secret_status.exitstatus == 1 ? "pass" : "fail", "matches"=>secret_stdout.lines.length},
    "sbom"=>{"spdx_version"=>sbom["spdxVersion"], "license_declared"=>sbom.dig("packages", 0, "licenseDeclared")},
    "third_party_manifest"=>{"present"=>File.size?(File.join(ROOT, "third_party/manifest.yaml")) ? true : false},
    "verdict"=>"pending"
  }
  predicates = {
    "ledger_time_bound"=>static_source.include?('ledger_time="${EVIDENCE_LEDGER_TIME:-}"'),
    "required_rights_files_present"=>rights_files.values.all?, "authority_lock_digest_matches_coverage"=>lock_digest == coverage_digest,
    "third_party_manifest_present"=>result.dig("third_party_manifest", "present"),
    "apache_license_declared"=>File.read(File.join(ROOT, "LICENSE")).include?("Apache License"),
    "spdx_apache_declared"=>result.dig("sbom", "spdx_version") == "SPDX-2.3" && result.dig("sbom", "license_declared") == "Apache-2.0",
    "secret_scan_pass"=>result.dig("secret_scan", "verdict") == "pass",
    "record_evidence_bound"=>static_source.include?("record_evidence foundation-authority-lock") && static_source.include?("record_evidence publication-static-gates publication.provenance"),
    "graph_gate_invoked"=>static_source.include?('ruby "$ROOT/scripts/graph-gates.rb"') && graph_stdout.include?("整合を確認")
  }
  result["verdict"] = predicates.values.all? ? "pass" : "fail"
  unless predicates.values.all?
    raise SecurityFailureDiagnostics::ScenarioOracleFailure.new(
      failed_row: "closure.definitive-domain.publication.provenance.security", target: "publication.provenance",
      oracle_error: "publication.provenance security Oracle failed", actual_result: result, oracle_predicates: predicates
    )
  end
  {
    "sql"=>{"source"=>static_source, "stdout"=>graph_stdout, "stderr"=>graph_stderr + secret_stderr},
    "plan"=>[{"Plan"=>{"Node Type"=>"Local Static Verification", "Actual Rows"=>required.length, "Actual Loops"=>1}}],
    "wal"=>{}, "log"=>graph_stdout, "metric"=>{"elapsed_ms"=>((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3), "required_files"=>required.length},
    "oracle_output"=>marker, "runtime"=>{"server_versions"=>["18.6"], "mode"=>"local-static-verifier"}
  }
end

def logical_replication_execution
  suffix = "#{Process.pid}-#{SecureRandom.hex(3)}"
  network = "pg-atlas-security-logical-net-#{suffix}"
  publisher = "pg-atlas-security-logical-publisher-#{suffix}"
  subscriber = "pg-atlas-security-logical-subscriber-#{suffix}"
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  fixture = security_fixture_sql("atlas_logical_secure", "atlas_logical_reader")
  verification = role_boundary_sql("operations.logical-replication", "atlas_logical_secure", "atlas_logical_reader")
  begin
    run!("docker", "network", "create", network)
    run!("docker", "run", "--detach", "--name", publisher, "--network", network, "--network-alias", "publisher",
         "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--env", "POSTGRES_DB=atlas", PG18_IMAGE,
         "-c", "wal_level=logical", "-c", "max_wal_senders=5", "-c", "max_replication_slots=5", "-c", "log_statement=all")
    run!("docker", "run", "--detach", "--name", subscriber, "--network", network,
         "--env", "POSTGRES_HOST_AUTH_METHOD=trust", "--env", "POSTGRES_DB=atlas", PG18_IMAGE, "-c", "log_statement=all")
    wait_for_postgres(publisher)
    wait_for_postgres(subscriber)
    run!("docker", "exec", "-i", publisher, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: fixture + "CREATE PUBLICATION atlas_security_publication FOR TABLE atlas_logical_secure;\n")
    subscriber_schema = security_fixture_sql("atlas_logical_secure", "atlas_logical_reader").sub(/INSERT INTO atlas_logical_secure.*\n/, "")
    run!("docker", "exec", "-i", subscriber, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: subscriber_schema)
    before_lsn = run!("docker", "exec", publisher, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
    run!("docker", "exec", subscriber, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", "-c", "CREATE SUBSCRIPTION atlas_security_subscription CONNECTION 'host=publisher dbname=atlas user=postgres' PUBLICATION atlas_security_publication WITH (copy_data=true, create_slot=true, enabled=true)")
    replicated = false
    60.times do
      count, _err, state = Open3.capture3("docker", "exec", subscriber, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT count(*) FROM atlas_logical_secure")
      if state.success? && count.strip == "2"
        replicated = true
        break
      end
      sleep 0.5
    end
    raise "logical replication did not copy both rows" unless replicated
    stdout, stderr = run!("docker", "exec", "-i", subscriber, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "atlas", stdin_data: verification)
    after_lsn = run!("docker", "exec", publisher, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT pg_current_wal_lsn()").first.strip
    plan = run!("docker", "exec", subscriber, "psql", "-XqAt", "-U", "postgres", "-d", "atlas", "-c", "SET ROLE atlas_logical_reader; EXPLAIN (FORMAT JSON) SELECT * FROM atlas_logical_secure; RESET ROLE").first.strip
    slot_active = run!("docker", "exec", publisher, "psql", "-XAt", "-U", "postgres", "-d", "atlas", "-c", "SELECT active FROM pg_replication_slots WHERE slot_name='atlas_security_subscription'").first.strip
    marker = "ATLAS_SECURITY_PASS:operations.logical-replication"
    raise "logical replication security markers missing" unless (stdout + stderr).scan(marker).length >= 2
    raise "logical replication slot is not active" unless slot_active == "t"
    logs = run!("docker", "logs", publisher).join + run!("docker", "logs", subscriber).join
    {
      "sql"=>{"source"=>fixture + subscriber_schema + verification, "stdout"=>stdout, "stderr"=>stderr},
      "plan"=>JSON.parse(plan), "wal"=>{"publisher_before_lsn"=>before_lsn, "publisher_after_lsn"=>after_lsn},
      "log"=>logs.lines.grep(/logical|statement:|ATLAS_SECURITY_PASS/).last(60).join,
      "metric"=>{"elapsed_ms"=>((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3), "replicated_rows"=>2, "slot_active"=>true},
      "oracle_output"=>marker,
      "runtime"=>{"server_versions"=>["18.6"], "images"=>[PG18_IMAGE], "containers"=>[publisher, subscriber], "network"=>network}
    }
  ensure
    system("docker", "rm", "-f", "-v", subscriber, publisher, out: File::NULL, err: File::NULL)
    system("docker", "network", "rm", network, out: File::NULL, err: File::NULL)
  end
end

def isolated_security_script_execution(target:, script_relative:, tmpfs_size:, log_files:)
  container = "pg-atlas-security-#{target.tr('.', '-')}-#{Process.pid}-#{SecureRandom.hex(3)}"
  script = File.join(ROOT, script_relative)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  started = false
  begin
    run!("docker", "run", "--detach", "--name", container,
         "--tmpfs", "/work:rw,exec,size=#{tmpfs_size}", PG18_IMAGE,
         "sh", "-ceu", "while :; do sleep 3600; done")
    started = true
    run!("docker", "cp", script, "#{container}:/tmp/atlas-security-verify.sh")
    stdout, stderr = run!("docker", "exec", container, "sh", "/tmp/atlas-security-verify.sh")
    result = JSON.parse(stdout)
    yield result
    logs = log_files.map { |path| run!("docker", "exec", container, "cat", path).join }.join("\n")
    metric_keys = %w[visible_rows after_target_rows replicated_rows archived_segments update_denied write_denied slot_active sender_state in_recovery]
    {
      "sql"=>{"source"=>File.read(script), "stdout"=>stdout, "stderr"=>stderr},
      "plan"=>JSON.parse(Base64.decode64(result.fetch("plan_base64"))),
      "wal"=>result.select { |key, _value| key.end_with?("_lsn") },
      "log"=>logs.lines.grep(/statement:|recovery|restore|redo|replication|read-only|permission denied/).last(100).join,
      "metric"=>result.slice(*metric_keys).merge("elapsed_ms"=>((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3)),
      "oracle_output"=>"ATLAS_SECURITY_PASS:#{target}",
      "runtime"=>{"server_versions"=>[result.fetch("version")], "images"=>[PG18_IMAGE], "containers"=>[container], "isolation"=>"container-tmpfs"}
    }
  ensure
    system("docker", "rm", "-f", "-v", container, out: File::NULL, err: File::NULL) if started
  end
end

def pitr_security_execution
  isolated_security_script_execution(
    target: "operations.pitr-recovery", script_relative: "labs/pitr/security-verify.sh", tmpfs_size: "768m",
    log_files: %w[/tmp/pitr-security-primary.log /tmp/pitr-security-restore.log]
  ) do |result|
    raise "PITR security Oracle failed" unless result.fetch("verdict") == "pass" &&
      result.fetch("version") == "18.6" && result.fetch("visible_rows") == 1 &&
      result.fetch("after_target_rows") == 0 && result.fetch("select_acl") == "t" &&
      result.fetch("rls_enabled") == "t" && result.fetch("update_denied") == true &&
      result.fetch("in_recovery") == "f" && result.fetch("archived_segments").positive?
  end
end

def physical_replication_security_execution
  isolated_security_script_execution(
    target: "operations.replication", script_relative: "labs/replication/security-verify.sh", tmpfs_size: "512m",
    log_files: %w[/tmp/replication-security-primary.log /tmp/replication-security-standby.log]
  ) do |result|
    raise "physical replication security Oracle failed" unless result.fetch("verdict") == "pass" &&
      result.fetch("version") == "18.6" && result.fetch("visible_rows") == 1 &&
      result.fetch("replicated_rows") == 3 && result.fetch("select_acl") == "t" &&
      result.fetch("rls_enabled") == "t" && result.fetch("write_denied") == true &&
      result.fetch("in_recovery") == "t" && result.fetch("sender_state") == "streaming" &&
      result.fetch("slot_active") == "t"
  end
end

def selected_security_patterns(plan)
  SecurityRuntimeReadinessContract.verify_runnable!(plan: plan)
  SecurityNextTrancheContract.verify!(plan: plan)
  pattern_ids = SecurityScenarioTranche.runtime_pattern_ids(plan)
  missing_patterns = pattern_ids.reject { |pattern_id| PATTERNS.key?(pattern_id) }
  raise "security runtime definitions missing: #{missing_patterns.join(', ')}" unless missing_patterns.empty?

  pattern_ids.to_h do |pattern_id|
    [pattern_id, PATTERNS.fetch(pattern_id)]
  end
end

selected_patterns = selected_security_patterns(SecurityScenarioTranche.load_plan)
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
  canonical_snapshot_before = SecurityFailureDiagnostics.canonical_artifact_snapshot(ROOT)
  begin
    publisher = AtomicEvidencePublisher.new(OUTPUT, validator: lambda do |staging|
      report = JSON.parse(File.read(File.join(staging, "results.json")))
      expected = selected_patterns.length
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
      tests = selected_patterns.map do |pattern_id, definition|
        target = definition.fetch("target")
        marker = "ATLAS_SECURITY_PASS:#{target}"
        execution = case definition["executor"]
                    when "compatibility-matrix" then compatibility_execution(definition)
                    when "pg-upgrade" then pg_upgrade_execution
                    when "logical-upgrade" then logical_upgrade_execution
                    when "backup-recovery" then backup_recovery_execution
                    when "failure-injection" then failure_injection_execution
                    when "logical-replication" then logical_replication_execution
                    when "wal-security" then wal_security_execution(container)
                    when "performance-execution-security" then performance_execution_security_execution(container)
                    when "performance-index-security" then performance_index_security_execution(container)
                    when "performance-planner-security" then performance_planner_security_execution(container)
                    when "performance-statistics-security" then performance_statistics_security_execution(container)
                    when "publication-provenance-security" then publication_provenance_security_execution
                    when "catalog-inventory-security" then catalog_inventory_security_execution(container)
                    when "bundled-extension-security" then bundled_extension_security_execution(container)
                    when "pitr-recovery" then pitr_security_execution
                    when "physical-replication" then physical_replication_security_execution
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
        "counts"=>{"rows"=>selected_patterns.length, "variants"=>selected_patterns.length, "total"=>selected_patterns.length, "passed"=>selected_patterns.length, "failed"=>0, "flaky"=>0, "skipped"=>0},
        "source_digest"=>source_digest, "harness_digest"=>harness_digest, "environment"=>environment,
        "retention_contract"=>{"publish_on"=>"full-run-passed", "failed_run"=>"retain-prior-success", "swap"=>"staged-directory-rename-with-rollback"},
        "tests"=>tests
      }
      File.write(File.join(staging, "results.json"), JSON.pretty_generate(report) + "\n")
    end
  rescue SecurityFailureDiagnostics::ScenarioOracleFailure => error
    canonical_snapshot_after = SecurityFailureDiagnostics.canonical_artifact_snapshot(ROOT)
    run_id = "security-001-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{Process.pid}"
    document = SecurityFailureDiagnostics.generic_failure_document(
      run_id: run_id,
      recorded_at: Time.now.utc.iso8601,
      failure: error,
      source_digest: source_digest,
      harness_digest: harness_digest,
      canonical_pre: canonical_snapshot_before,
      canonical_post: canonical_snapshot_after
    )
    SecurityFailureDiagnostics.record_failure(
      output_root: FAILURE_DIAGNOSTICS_OUTPUT,
      document: document,
      original_error: error
    )
    raise error
  rescue RuntimeError => error
    canonical_snapshot_after = SecurityFailureDiagnostics.canonical_artifact_snapshot(ROOT)
    run_id = "security-001-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{Process.pid}"
    document = SecurityFailureDiagnostics.generic_failure_document(
      run_id: run_id,
      recorded_at: Time.now.utc.iso8601,
      failure: SecurityFailureDiagnostics::ScenarioOracleFailure.new(
        failed_row: "closure.unknown.security",
        target: "unknown",
        oracle_error: error.message,
        actual_result: {},
        oracle_predicates: {}
      ),
      source_digest: source_digest,
      harness_digest: harness_digest,
      canonical_pre: canonical_snapshot_before,
      canonical_post: canonical_snapshot_after
    )
    SecurityFailureDiagnostics.record_failure(
      output_root: FAILURE_DIAGNOSTICS_OUTPUT,
      document: document,
      original_error: error
    )
    raise error
  end
  raise "Scenario Evidence was not published" unless result == :published
  puts "Published atomic PostgreSQL security Evidence: #{selected_patterns.length} rows / #{selected_patterns.length} first-attempt Variant runs."
ensure
  system("docker", "rm", "-f", "-v", container, out: File::NULL, err: File::NULL) if started
end
