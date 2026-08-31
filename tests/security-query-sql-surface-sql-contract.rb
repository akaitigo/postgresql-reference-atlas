#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_next_tranche_row_contracts"

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
section = source[/def query_sql_surface_security_execution\(container\)(.*?)^end$/m, 1]
contract = SecurityNextTrancheRowContracts.contracts.find { |row| row.fetch("pattern_id") == "definitive-domain.query.sql-surface" } or abort("query.sql-surface row contract missing")
OBSERVATION_INSERT = "INSERT INTO atlas_sql_surface_observation DEFAULT VALUES;"
EXACT_OBSERVATION_GRANT = "GRANT SELECT, UPDATE ON atlas_sql_surface_observation TO atlas_sql_surface_writer;"
EXACT_ROLE = "SET ROLE atlas_sql_surface_writer;"
RETURNING_UPDATE_BLOCK = "      UPDATE atlas_sql_surface_observation\n      SET returned_id = (SELECT id FROM inserted),\n          returned_note = (SELECT note FROM inserted);"
VISIBILITY_UPDATE_BLOCK = "      UPDATE atlas_sql_surface_observation\n      SET visible_rows = (SELECT count(*)::integer FROM atlas_sql_surface_secure WHERE tenant = 'atlas_sql_surface_writer');\n      GET DIAGNOSTICS updated_rows = ROW_COUNT;\n      IF updated_rows <> 1 THEN\n        RAISE EXCEPTION 'atlas_sql_surface_observation visible_rows update expected 1 row, got %', updated_rows;\n      END IF;"
OUTER_RESCUE_BLOCK = <<~BLOCK.chomp
DO $atlas$
    DECLARE observed_state text;
    DECLARE updated_rows bigint;
    BEGIN
      BEGIN
        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 1, 100, 'duplicate');
BLOCK
SIBLING_CHECK_BLOCK = "      END;\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 2, -1, 'invalid');"
SIBLING_REFUSAL_BLOCK = "      END;\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('postgres', 2, 100, 'escape');"

abort "query.sql-surface section is missing" unless section

def refusal_block(section)
  anchor = "DO $atlas$\n    DECLARE observed_state text;\n    DECLARE updated_rows bigint;\n    BEGIN"
  start = section.index(anchor) or raise "query.sql-surface refusal DO block missing"
  finish = section.index("    $atlas$;", start) or raise "query.sql-surface refusal DO block terminator missing"
  section[start, finish - start + "    $atlas$;".length]
end

def verify_query_sql_surface_section!(section)
  block = refusal_block(section)
  role_index = section.index(EXACT_ROLE)
  raise "query.sql-surface must seed exactly one observation row before tenant role" unless role_index && section.scan(OBSERVATION_INSERT).length == 1 && section.index(OBSERVATION_INSERT) < role_index
  raise "query.sql-surface must not allow tenant observation inserts" unless section.include?(EXACT_OBSERVATION_GRANT) && !section.include?("GRANT ALL ON atlas_sql_surface_observation TO atlas_sql_surface_writer;")
  raise "query.sql-surface must terminate every DO block with END;" if section.include?("\n    END\n    $atlas$;")
  raise "query.sql-surface must update visible_rows in a statement after RETURNING update under tenant role" unless section.include?(RETURNING_UPDATE_BLOCK) && section.include?(VISIBILITY_UPDATE_BLOCK) && section.index(RETURNING_UPDATE_BLOCK) < section.index(VISIBILITY_UPDATE_BLOCK)
  raise "query.sql-surface outer BEGIN must directly contain the first nested BEGIN refusal block" unless block.include?(OUTER_RESCUE_BLOCK)
  raise "query.sql-surface must keep exactly three sibling nested refusal blocks inside the outer DO block" unless block.scan(/\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure\(/).length == 3
  raise "query.sql-surface must keep sibling refusal/check blocks inside the outer DO block" unless block.include?(SIBLING_CHECK_BLOCK) && block.include?(SIBLING_REFUSAL_BLOCK)
  raise "query.sql-surface must keep exact single-row observation updates" unless section.scan("GET DIAGNOSTICS updated_rows = ROW_COUNT;").length == 6 && section.include?("atlas_sql_surface_observation insert/update expected 1 row, got %") && section.include?("atlas_sql_surface_observation visible_rows update expected 1 row, got %") && section.include?("atlas_sql_surface_observation plan update expected 1 row, got %") && section.include?("atlas_sql_surface_observation duplicate update expected 1 row, got %") && section.include?("atlas_sql_surface_observation check update expected 1 row, got %") && section.include?("atlas_sql_surface_observation refusal update expected 1 row, got %")
  raise "query.sql-surface must keep exact final observation cardinality and visible_rows verdict" unless section.include?("atlas_sql_surface_observation final cardinality expected 1 row, got %") && section.include?("'observation_rows', (SELECT count(*)::integer FROM atlas_sql_surface_observation),") && section.include?("'visible_rows', visible_rows,") && section.include?("returned_id = 1 AND returned_note = 'created' AND visible_rows = 1")
  raise "query.sql-surface must use row-specific structured command and JSON failure mapping" unless section.include?("psql_json_execution_for_row!(") && section.include?('failed_row: "closure.definitive-domain.query.sql-surface.security"') && section.include?('target: "query.sql-surface"') && section.include?('phase: "runtime"')
end

errors = []
contract.fetch("sql_fragments").each do |fragment|
  errors << "missing SQL fragment: #{fragment}" unless section.include?(fragment)
end
contract.fetch("forbidden_sql_fragments").each do |fragment|
  errors << "forbidden SQL fragment present: #{fragment}" if section.include?(fragment)
end
errors << "structured failure binding drifted" unless section.include?('failed_row: "closure.definitive-domain.query.sql-surface.security"') &&
  section.include?('target: "query.sql-surface"') &&
  section.include?('oracle_error: "query.sql-surface security Oracle failed"')
abort errors.join("\n") unless errors.empty?
verify_query_sql_surface_section!(section)

current_user_regression = section.sub("USING (tenant = 'atlas_sql_surface_writer')", "USING (tenant = current_user)")
abort "current_user sql-surface policy regression was accepted" unless current_user_regression.include?("USING (tenant = current_user)")
abort "query.sql-surface contract no longer forbids current_user regression" unless contract.fetch("forbidden_sql_fragments").include?("current_user")

grant_update_regression = section.sub("GRANT SELECT, INSERT ON atlas_sql_surface_secure TO atlas_sql_surface_writer;", "GRANT SELECT, INSERT, UPDATE ON atlas_sql_surface_secure TO atlas_sql_surface_writer;")
abort "UPDATE grant regression was accepted" unless grant_update_regression.include?("UPDATE ON atlas_sql_surface_secure")
abort "query.sql-surface contract no longer forbids UPDATE grant regression" unless contract.fetch("forbidden_sql_fragments").include?("GRANT UPDATE")

begin
  verify_query_sql_surface_section!(section.sub("    INSERT INTO atlas_sql_surface_observation DEFAULT VALUES;\n", ""))
  abort "query.sql-surface missing observation seed regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("seed exactly one observation row")
end

begin
  verify_query_sql_surface_section!(section.sub(OBSERVATION_INSERT, "#{OBSERVATION_INSERT}\n    #{OBSERVATION_INSERT}"))
  abort "query.sql-surface duplicated observation seed regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("seed exactly one observation row")
end

begin
  verify_query_sql_surface_section!(section.sub(EXACT_OBSERVATION_GRANT, "GRANT ALL ON atlas_sql_surface_observation TO atlas_sql_surface_writer;"))
  abort "query.sql-surface tenant observation insert regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("must not allow tenant observation inserts")
end

begin
  verify_query_sql_surface_section!(section.sub(EXACT_ROLE + "\n", ""))
  abort "query.sql-surface missing SET ROLE regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("seed exactly one observation row before tenant role")
end

begin
  verify_query_sql_surface_section!(section.sub("    END;\n    $atlas$;", "    END\n    $atlas$;"))
  abort "query.sql-surface DO semicolon regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("terminate every DO block")
end

begin
  verify_query_sql_surface_section!(section.sub("    BEGIN\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 1, 100, 'duplicate');", "    BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 1, 100, 'duplicate');"))
  abort "query.sql-surface first nested BEGIN regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("outer BEGIN must directly contain the first nested BEGIN")
end

begin
  verify_query_sql_surface_section!(section.sub("      END;\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 2, -1, 'invalid');", "    END;\n    BEGIN\n      INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 2, -1, 'invalid');"))
  abort "query.sql-surface sibling refusal block escaped outer DO regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sibling refusal/check blocks inside the outer DO block") || e.message.include?("exactly three sibling nested refusal blocks")
end

begin
  same_statement_regression = section.sub(
    RETURNING_UPDATE_BLOCK + "\n      GET DIAGNOSTICS updated_rows = ROW_COUNT;\n      IF updated_rows <> 1 THEN\n        RAISE EXCEPTION 'atlas_sql_surface_observation insert/update expected 1 row, got %', updated_rows;\n      END IF;\n" + VISIBILITY_UPDATE_BLOCK,
    "      UPDATE atlas_sql_surface_observation\n      SET returned_id = (SELECT id FROM inserted),\n          returned_note = (SELECT note FROM inserted),\n          visible_rows = (SELECT count(*)::integer FROM atlas_sql_surface_secure WHERE tenant = 'atlas_sql_surface_writer');\n      GET DIAGNOSTICS updated_rows = ROW_COUNT;\n      IF updated_rows <> 1 THEN\n        RAISE EXCEPTION 'atlas_sql_surface_observation insert/update expected 1 row, got %', updated_rows;\n      END IF;\n"
  )
  verify_query_sql_surface_section!(same_statement_regression)
  abort "query.sql-surface same-statement visibility snapshot regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("visible_rows in a statement after RETURNING update")
end

begin
  verify_query_sql_surface_section!(section.sub("SET visible_rows = (SELECT count(*)::integer FROM atlas_sql_surface_secure WHERE tenant = 'atlas_sql_surface_writer');", "SET visible_rows = (SELECT count(*)::integer FROM inserted);"))
  abort "query.sql-surface inserted CTE visibility regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("visible_rows in a statement after RETURNING update")
end

begin
  verify_query_sql_surface_section!(section.sub("        GET DIAGNOSTICS updated_rows = ROW_COUNT;\n        IF updated_rows <> 1 THEN\n          RAISE EXCEPTION 'atlas_sql_surface_observation duplicate update expected 1 row, got %', updated_rows;\n        END IF;\n", ""))
  abort "query.sql-surface zero-row update guard regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("single-row observation updates")
end

begin
  verify_query_sql_surface_section!(section.sub("atlas_sql_surface_observation final cardinality expected 1 row, got %", "atlas_sql_surface_observation final cardinality removed"))
  abort "query.sql-surface final observation cardinality regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("final observation cardinality and visible_rows verdict")
end

begin
  verify_query_sql_surface_section!(section.sub("returned_id = 1 AND returned_note = 'created' AND visible_rows = 1", "returned_id = 1 AND returned_note = 'created' AND visible_rows = 0"))
  abort "query.sql-surface expected0 visible_rows regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("final observation cardinality and visible_rows verdict")
end

begin
  verify_query_sql_surface_section!(section.sub("psql_json_execution_for_row!(", "psql_json_execution("))
  abort "query.sql-surface generic unknown mapping regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("row-specific structured command and JSON failure mapping")
end

puts "query.sql-surface SQL contractを検証しました: exact SQL fragments, separate visible_rows statement, nested sibling PL/pgSQL refusal blocks, observation exact1, END; termination, and structured failure binding are fixed"
