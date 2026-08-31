#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_next_tranche_row_contracts"

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
section = source[/def query_security_security_execution\(container\)(.*?)^def query_sql_surface_security_execution/m, 1]
contract = SecurityNextTrancheRowContracts.contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.security" } or abort("query.security row contract missing")
OBSERVATION_INSERT = "INSERT INTO atlas_query_security_observation DEFAULT VALUES;"
EXACT_OBSERVATION_GRANT = "GRANT SELECT, UPDATE ON atlas_query_security_observation TO tenant_app;"

abort "query.security section is missing" unless section

def verify_query_security_section!(section)
  dblink_statement = "SELECT dblink_connect('tenant1', 'host=127.0.0.1 dbname=atlas user=tenant_app password=tenant-atlas options=-capp.tenant_id=1');"
  raise "query.security must bootstrap role/table/policy before cross-session dblink" unless section.include?("bootstrap_sql = <<~SQL") && section.include?("runtime_sql = <<~SQL")
  commit_index = section.index("COMMIT;")
  observation_insert_index = section.index(OBSERVATION_INSERT)
  set_role_index = section.index("SET ROLE tenant_app;")
  dblink_index = section.index(dblink_statement)
  raise "query.security must not target the wrong database" if section.include?("dbname=postgres")
  raise "query.security must not force a socket path in dblink" if section.include?("host=/var/run/postgresql") || section.include?("host=/tmp")
  raise "query.security must seed exactly one observation row before tenant role" unless section.scan(OBSERVATION_INSERT).length == 1 && observation_insert_index && set_role_index && observation_insert_index < set_role_index
  raise "query.security must not allow tenant observation inserts" unless section.include?(EXACT_OBSERVATION_GRANT) && !section.include?("GRANT ALL ON atlas_query_security_observation TO tenant_app;")
  raise "query.security must enforce exact single-row observation updates" unless section.scan("GET DIAGNOSTICS updated_rows = ROW_COUNT;").length >= 3 && section.scan("IF updated_rows <> 1 THEN").length >= 3
  raise "query.security must enforce exact final observation cardinality" unless section.include?("SELECT count(*) INTO observation_rows FROM atlas_query_security_observation;") && section.include?("atlas_query_security_observation final cardinality expected 1 row, got %") && section.include?("'observation_rows', (SELECT count(*)::integer FROM atlas_query_security_observation),") && section.include?("WHEN (SELECT count(*)::integer FROM atlas_query_security_observation) = 1 AND visible_rows = 1")
  raise "query.security dblink target drifted" unless dblink_index
  raise "query.security must commit bootstrap before cross-session dblink" unless commit_index && commit_index < dblink_index
  raise "query.security structured runtime failure mapping drifted" unless section.include?('failed_row: "closure.definitive-domain.query.security.security"') &&
    section.include?('target: "query.security"') &&
    section.include?('phase: "bootstrap"') &&
    section.include?('phase: "cross-session-refusal"') &&
    section.include?('SecurityJsonOutput.command_failure_result(') &&
    section.include?('exit_status:') &&
    section.include?('stdout:') &&
    section.include?('stderr:') &&
    section.include?('SecurityJsonOutput.parse_single_json_object!(') &&
    section.include?('phase: "json-parse"')
end

errors = []
contract.fetch("sql_fragments").each do |fragment|
  errors << "missing SQL fragment: #{fragment}" unless section.include?(fragment)
end
contract.fetch("forbidden_sql_fragments").each do |fragment|
  errors << "forbidden SQL fragment present: #{fragment}" if section.include?(fragment)
end
errors << "structured failure binding drifted" unless section.include?('failed_row: "closure.definitive-domain.query.security.security"') &&
  section.include?('target: "query.security"') &&
  section.include?('oracle_error: "query.security security Oracle failed"')
abort errors.join("\n") unless errors.empty?
verify_query_security_section!(section)

bypassrls_regression = section.sub("NOSUPERUSER NOCREATEDB NOCREATEROLE", "NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS")
abort "BYPASSRLS regression was accepted" unless bypassrls_regression.include?("BYPASSRLS")
abort "query.security contract no longer forbids BYPASSRLS regression" unless contract.fetch("forbidden_sql_fragments").include?("ALTER ROLE tenant_app BYPASSRLS")

row_security_off = section.sub("SELECT dblink_connect('tenant1'", "SET row_security = off;\n    SELECT dblink_connect('tenant1'")
abort "row_security=off regression was accepted" unless row_security_off.include?("SET row_security = off;")
abort "query.security contract no longer forbids row_security=off regression" unless contract.fetch("forbidden_sql_fragments").include?("SET row_security = off")

begin
  verify_query_security_section!(section.sub("    INSERT INTO atlas_query_security_observation DEFAULT VALUES;\n", ""))
  abort "observation row seed removal was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("seed exactly one observation row")
end

begin
  verify_query_security_section!(section.sub("GRANT SELECT, UPDATE ON atlas_query_security_observation TO tenant_app;", "GRANT ALL ON atlas_query_security_observation TO tenant_app;"))
  abort "tenant observation insert grant regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("must not allow tenant observation inserts")
end

begin
  verify_query_security_section!(section.sub("      GET DIAGNOSTICS updated_rows = ROW_COUNT;\n      IF updated_rows <> 1 THEN\n        RAISE EXCEPTION 'atlas_query_security_observation plan update expected 1 row, got %', updated_rows;\n      END IF;\n", ""))
  abort "observation update row-count guard regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("exact single-row observation updates")
end

begin
  verify_query_security_section!(section.sub("    DO $atlas$\n    DECLARE observation_rows bigint;\n    BEGIN\n      SELECT count(*) INTO observation_rows FROM atlas_query_security_observation;\n      IF observation_rows <> 1 THEN\n        RAISE EXCEPTION 'atlas_query_security_observation final cardinality expected 1 row, got %', observation_rows;\n      END IF;\n    END;\n    $atlas$;\n", ""))
  abort "final observation cardinality guard regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("exact final observation cardinality")
end

begin
  duplicated_observation_seed = section.sub(OBSERVATION_INSERT, "#{OBSERVATION_INSERT}\n    #{OBSERVATION_INSERT}")
  verify_query_security_section!(duplicated_observation_seed)
  abort "duplicated observation seed was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("seed exactly one observation row")
end

begin
  verify_query_security_section!(section.sub("    COMMIT;\n", ""))
  abort "pre-commit dblink visibility regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("commit bootstrap")
end

begin
  verify_query_security_section!(section.sub("host=127.0.0.1 ", ""))
  abort "missing dblink host regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("dblink target drifted")
end

begin
  verify_query_security_section!(section.sub("dbname=atlas", "dbname=postgres"))
  abort "wrong dblink database regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("wrong database")
end

begin
  verify_query_security_section!(section.sub("password=tenant-atlas", "password=tenant-wrong"))
  abort "wrong dblink password regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("dblink target drifted")
end

begin
  verify_query_security_section!(section.sub("options=-capp.tenant_id=1", "host=/tmp options=-capp.tenant_id=1"))
  abort "wrong dblink socket regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("socket path")
end

puts "query.security SQL contractを検証しました: committed bootstrap, exact loopback dblink target, single-row observation guards, forbidden BYPASSRLS/row_security=off regressions, and structured failure binding are fixed"
