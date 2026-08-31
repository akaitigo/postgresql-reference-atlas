#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_next_tranche_row_contracts"

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
section = source[/def query_types_constraints_security_execution\(container\)(.*?)^end$/m, 1]
contract = SecurityNextTrancheRowContracts.contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.types-constraints" } or abort("query.types-constraints row contract missing")
OBSERVATION_INSERT = "INSERT INTO atlas_typed_order_observation DEFAULT VALUES;"
EXACT_OBSERVATION_GRANT = "GRANT SELECT, UPDATE ON atlas_typed_order_observation TO atlas_typed_order_writer;"
OUTER_RESCUE_BLOCK = <<~BLOCK.chomp
DO $atlas$
    DECLARE observed_state text;
    DECLARE updated_rows bigint;
    BEGIN
      BEGIN
        INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)
BLOCK
SIBLING_REFUSAL_BLOCK = "      END;\n      BEGIN\n        INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)\n        VALUES ('postgres', 'confirmed', 1, ARRAY['escape'], '{\"name\":\"escape\"}', tstzrange('2026-01-01', '2026-01-02'), datemultirange(daterange('2026-01-01', '2026-01-02', '[)')), '192.0.2.20/24');"

abort "query.types-constraints section is missing" unless section

def refusal_block(section)
  anchor = "DO $atlas$\n    DECLARE observed_state text;\n    DECLARE updated_rows bigint;\n    BEGIN"
  start = section.index(anchor) or raise "query.types-constraints refusal DO block missing"
  finish = section.index("    $atlas$;", start) or raise "query.types-constraints refusal DO block terminator missing"
  section[start, finish - start + "    $atlas$;".length]
end

def verify_query_types_constraints_section!(section)
  block = refusal_block(section)
  raise "query.types-constraints must seed exactly one observation row before tenant role" unless section.scan(OBSERVATION_INSERT).length == 1 && section.index(OBSERVATION_INSERT) < section.index("SET ROLE atlas_typed_order_writer;")
  raise "query.types-constraints must not allow tenant observation inserts" unless section.include?(EXACT_OBSERVATION_GRANT) && !section.include?("GRANT ALL ON atlas_typed_order_observation TO atlas_typed_order_writer;")
  raise "query.types-constraints must terminate every DO block with END;" if section.include?("\n    END\n    $atlas$;")
  raise "query.types-constraints outer BEGIN must directly contain the first nested BEGIN refusal block" unless block.include?(OUTER_RESCUE_BLOCK)
  raise "query.types-constraints must keep exactly two sibling nested refusal blocks inside the outer DO block" unless block.scan(/\n      BEGIN\n        INSERT INTO atlas_typed_order_secure\(/).length == 2
  raise "query.types-constraints must keep sibling refusal blocks inside the outer DO block" unless block.include?(SIBLING_REFUSAL_BLOCK)
  raise "query.types-constraints must keep exact single-row observation updates" unless section.scan("GET DIAGNOSTICS updated_rows = ROW_COUNT;").length == 4 && section.include?("atlas_typed_order_observation insert/update expected 1 row, got %") && section.include?("atlas_typed_order_observation plan update expected 1 row, got %") && section.include?("atlas_typed_order_observation invalid-domain update expected 1 row, got %") && section.include?("atlas_typed_order_observation refusal update expected 1 row, got %")
  raise "query.types-constraints must keep exact final observation cardinality" unless section.include?("atlas_typed_order_observation final cardinality expected 1 row, got %") && section.include?("'observation_rows', (SELECT count(*)::integer FROM atlas_typed_order_observation),")
  raise "query.types-constraints must use row-specific structured command and JSON failure mapping" unless section.include?("psql_json_execution_for_row!(") && section.include?('failed_row: "closure.definitive-domain.query.types-constraints.security"') && section.include?('target: "query.types-constraints"') && section.include?('phase: "runtime"')
end

errors = []
contract.fetch("sql_fragments").each do |fragment|
  errors << "missing SQL fragment: #{fragment}" unless section.include?(fragment)
end
contract.fetch("forbidden_sql_fragments").each do |fragment|
  errors << "forbidden SQL fragment present: #{fragment}" if section.include?(fragment)
end
errors << "structured failure binding drifted" unless section.include?('failed_row: "closure.definitive-domain.query.types-constraints.security"') &&
  section.include?('target: "query.types-constraints"') &&
  section.include?('oracle_error: "query.types-constraints security Oracle failed"')
abort errors.join("\n") unless errors.empty?
verify_query_types_constraints_section!(section)

current_user_regression = section.sub("USING (tenant = 'atlas_typed_order_writer')", "USING (tenant = current_user)")
abort "current_user types-constraints policy regression was accepted" unless current_user_regression.include?("USING (tenant = current_user)")
abort "query.types-constraints contract no longer forbids current_user regression" unless contract.fetch("forbidden_sql_fragments").include?("current_user")

public_policy_regression = section.sub("TO atlas_typed_order_writer", "TO PUBLIC")
abort "PUBLIC types-constraints policy regression was accepted" unless public_policy_regression.include?("TO PUBLIC")
abort "query.types-constraints contract no longer models PUBLIC policy regression" unless contract.fetch("negative_cases").include?("public_policy_regression")

bypassrls_regression = section.sub("CREATE ROLE atlas_typed_order_writer LOGIN PASSWORD 'atlas-types';", "CREATE ROLE atlas_typed_order_writer LOGIN PASSWORD 'atlas-types' BYPASSRLS;")
abort "BYPASSRLS types-constraints regression was accepted" unless bypassrls_regression.include?("BYPASSRLS")
abort "query.types-constraints contract no longer forbids BYPASSRLS regression" unless contract.fetch("forbidden_sql_fragments").include?("ALTER ROLE atlas_typed_order_writer BYPASSRLS")

begin
  verify_query_types_constraints_section!(section.sub("    INSERT INTO atlas_typed_order_observation DEFAULT VALUES;\n", ""))
  abort "query.types-constraints missing observation seed regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("seed exactly one observation row")
end

begin
  verify_query_types_constraints_section!(section.sub(OBSERVATION_INSERT, "#{OBSERVATION_INSERT}\n    #{OBSERVATION_INSERT}"))
  abort "query.types-constraints duplicated observation seed regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("seed exactly one observation row")
end

begin
  verify_query_types_constraints_section!(section.sub(EXACT_OBSERVATION_GRANT, "GRANT ALL ON atlas_typed_order_observation TO atlas_typed_order_writer;"))
  abort "query.types-constraints tenant observation insert regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("must not allow tenant observation inserts")
end

begin
  verify_query_types_constraints_section!(section.sub("    END;\n    $atlas$;", "    END\n    $atlas$;"))
  abort "query.types-constraints DO semicolon regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("terminate every DO block")
end

begin
  verify_query_types_constraints_section!(section.sub("    BEGIN\n      BEGIN\n        INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)", "    BEGIN\n        INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)"))
  abort "query.types-constraints first nested BEGIN regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("outer BEGIN must directly contain the first nested BEGIN")
end

begin
  verify_query_types_constraints_section!(section.sub("      END;\n      BEGIN\n        INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)\n        VALUES ('postgres', 'confirmed', 1, ARRAY['escape'], '{\"name\":\"escape\"}', tstzrange('2026-01-01', '2026-01-02'), datemultirange(daterange('2026-01-01', '2026-01-02', '[)')), '192.0.2.20/24');", "    END;\n    BEGIN\n      INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)\n      VALUES ('postgres', 'confirmed', 1, ARRAY['escape'], '{\"name\":\"escape\"}', tstzrange('2026-01-01', '2026-01-02'), datemultirange(daterange('2026-01-01', '2026-01-02', '[)')), '192.0.2.20/24');"))
  abort "query.types-constraints sibling refusal block escaped outer DO regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sibling refusal blocks inside the outer DO block") || e.message.include?("exactly two sibling nested refusal blocks")
end

begin
  verify_query_types_constraints_section!(section.sub("        GET DIAGNOSTICS updated_rows = ROW_COUNT;\n        IF updated_rows <> 1 THEN\n          RAISE EXCEPTION 'atlas_typed_order_observation invalid-domain update expected 1 row, got %', updated_rows;\n        END IF;\n", ""))
  abort "query.types-constraints zero-row update guard regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("single-row observation updates")
end

begin
  verify_query_types_constraints_section!(section.sub("atlas_typed_order_observation final cardinality expected 1 row, got %", "atlas_typed_order_observation final cardinality removed"))
  abort "query.types-constraints final observation cardinality regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("final observation cardinality")
end

begin
  verify_query_types_constraints_section!(section.sub("psql_json_execution_for_row!(", "psql_json_execution("))
  abort "query.types-constraints generic unknown mapping regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("row-specific structured command and JSON failure mapping")
end

puts "query.types-constraints SQL contractを検証しました: exact SQL fragments, nested sibling PL/pgSQL refusal blocks, observation exact1, END; termination, and structured failure binding are fixed"
