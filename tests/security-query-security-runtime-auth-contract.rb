#!/usr/bin/env ruby
# frozen_string_literal: true

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
section = source[/def query_security_security_execution\(container\)(.*?)^def query_sql_surface_security_execution/m, 1]
main_run = source[/selected_patterns, runtime_preflight = selected_security_patterns\(SecurityScenarioTranche\.load_plan\)(.*?)publisher = AtomicEvidencePublisher\.new/m, 1]

abort "query.security section is missing" unless section
abort "security main runtime block is missing" unless main_run

EXACT_DBLINK = "SELECT dblink_connect('tenant1', 'host=127.0.0.1 dbname=atlas user=tenant_app password=tenant-atlas options=-capp.tenant_id=1');"
EXACT_INITDB_ARGS = '"POSTGRES_INITDB_ARGS=#{ROOT_POSTGRES_INITDB_ARGS}"'

def verify_query_security_runtime_auth!(section, main_run)
  raise "query.security must use loopback host dblink with exact tenant password" unless section.include?(EXACT_DBLINK)
  raise "query.security must not omit loopback host from dblink target" if section.include?("SELECT dblink_connect('tenant1', 'dbname=atlas user=tenant_app password=tenant-atlas options=-capp.tenant_id=1');")
  raise "query.security must publish bounded host-rule rows" unless section.include?("'host_rule_rows', COALESCE((") &&
    section.scan("'line_number', line_number").length >= 2 &&
    section.scan("'type', type").length >= 2 &&
    section.scan("'database', database").length >= 2 &&
    section.scan("'user_name', user_name").length >= 2 &&
    section.scan("'address', address").length >= 2 &&
    section.scan("'auth_method', auth_method").length >= 2 &&
    section.scan("'error', error").length >= 2
  raise "query.security must publish the first matching host rule for 127.0.0.1 / tenant_app / atlas" unless section.include?("'effective_host_rule', COALESCE((") &&
    section.include?("database @> ARRAY['atlas']::text[]") &&
    section.include?("user_name @> ARRAY['tenant_app']::text[]") &&
    section.include?("address = '127.0.0.1'") &&
    section.scan("ORDER BY line_number\n          LIMIT 1").length >= 2 &&
    section.include?("LIMIT 1")
  raise "query.security must verify the first matching host rule is scram-sha-256" unless section.include?("'host_scram_rule', COALESCE((") &&
    section.scan("SELECT auth_method = 'scram-sha-256'").length == 2 &&
    !section.include?("SELECT auth_method = 'md5'") &&
    !section.include?("SELECT auth_method = 'trust'") &&
    !section.include?("bool_or(auth_method = 'scram-sha-256')")
  raise "security main runtime container must use POSTGRES_PASSWORD initialization" unless main_run.include?('"POSTGRES_PASSWORD=#{ROOT_POSTGRES_PASSWORD}"') ||
    main_run.include?('"POSTGRES_PASSWORD=postgres-atlas-root"')
  raise "security main runtime container must use exact initdb args" unless main_run.include?(EXACT_INITDB_ARGS) ||
    main_run.include?('"POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256 --auth-local=trust"')
  raise "security main runtime container must not use POSTGRES_HOST_AUTH_METHOD=trust" if main_run.include?("POSTGRES_HOST_AUTH_METHOD=trust")
end

verify_query_security_runtime_auth!(section, main_run)

begin
  verify_query_security_runtime_auth!(section.sub("host=127.0.0.1 ", ""), main_run)
  abort "query.security missing host regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("loopback host")
end

begin
  verify_query_security_runtime_auth!(section.sub("password=tenant-atlas", "password=tenant-wrong"), main_run)
  abort "query.security wrong password regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("exact tenant password")
end

begin
  verify_query_security_runtime_auth!(section, main_run.sub(EXACT_INITDB_ARGS, '"POSTGRES_INITDB_ARGS=--auth-local=trust"'))
  abort "query.security initdb args regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("exact initdb args")
end

begin
  verify_query_security_runtime_auth!(section, main_run.sub(EXACT_INITDB_ARGS, '"POSTGRES_HOST_AUTH_METHOD=trust"'))
  abort "query.security localhost trust regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("exact initdb args") || e.message.include?("must not use POSTGRES_HOST_AUTH_METHOD=trust")
end

begin
  verify_query_security_runtime_auth!(section.sub("SELECT auth_method = 'scram-sha-256'", "SELECT auth_method = 'md5'"), main_run)
  abort "query.security host md5 regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("scram-sha-256")
end

begin
  verify_query_security_runtime_auth!(section.sub("SELECT auth_method = 'scram-sha-256'", "SELECT auth_method = 'trust'"), main_run)
  abort "query.security host trust regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("scram-sha-256")
end

begin
  verify_query_security_runtime_auth!(section.sub("'auth_method', auth_method", "'auth_method', NULL"), main_run)
  abort "query.security host auth_method null regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("bounded host-rule rows")
end

begin
  verify_query_security_runtime_auth!(section.sub("'error', error", "'error', 'parsed error'"), main_run)
  abort "query.security host-rule error regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("bounded host-rule rows")
end

begin
  verify_query_security_runtime_auth!(section.sub("ORDER BY line_number\n          LIMIT 1", "ORDER BY line_number DESC\n          LIMIT 1"), main_run)
  abort "query.security host-rule order regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("first matching host rule")
end

begin
  verify_query_security_runtime_auth!(section.sub("SELECT auth_method = 'scram-sha-256'", "SELECT true"), main_run)
  abort "query.security scram append-only regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("scram-sha-256")
end

begin
  verify_query_security_runtime_auth!(section.sub("SELECT auth_method = 'scram-sha-256'", "SELECT bool_or(auth_method = 'scram-sha-256')"), main_run)
  abort "query.security bool_or false-positive regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("scram-sha-256")
end

puts "query.security runtime auth contractを検証しました: initdb auth args, loopback dblink, ordered host pg_hba proof, and main-runtime trust rejection are fixed"
