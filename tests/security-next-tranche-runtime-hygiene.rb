#!/usr/bin/env ruby
# frozen_string_literal: true

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))

def section(source, name, next_name = nil)
  if next_name
    source[/def #{Regexp.escape(name)}\(container\)(.*?)^def #{Regexp.escape(next_name)}\(container\)/m, 1]
  else
    source[/def #{Regexp.escape(name)}\(container\)(.*?)^end$/m, 1]
  end
end

partitioning = section(source, "query_partitioning_security_execution", "query_security_security_execution") or abort("query.partitioning runtime section missing")
query_security = section(source, "query_security_security_execution", "query_sql_surface_security_execution") or abort("query.security runtime section missing")
sql_surface = section(source, "query_sql_surface_security_execution", "query_types_constraints_security_execution") or abort("query.sql-surface runtime section missing")
types_constraints = section(source, "query_types_constraints_security_execution") or abort("query.types-constraints runtime section missing")

SECTIONS = {
  "query.partitioning"=>{
    "body"=>partitioning,
    "seed"=>"INSERT INTO atlas_partition_observation(q1_rows, q2_rows, default_rows)",
    "grant"=>"GRANT SELECT, UPDATE ON atlas_partition_observation TO atlas_partition_reader;",
    "forbidden_grant"=>"GRANT ALL ON atlas_partition_observation TO atlas_partition_reader;",
    "failed_row"=>'failed_row: "closure.definitive-domain.query.partitioning.security"',
    "target"=>'target: "query.partitioning"',
    "helper"=>'psql_json_execution_for_row!(',
    "final_cardinality"=>"atlas_partition_observation final cardinality expected 1 row, got %",
    "row_count_guard"=>"atlas_partition_observation plan update expected 1 row, got %"
  },
  "query.security"=>{
    "body"=>query_security,
    "seed"=>"INSERT INTO atlas_query_security_observation DEFAULT VALUES;",
    "grant"=>"GRANT SELECT, UPDATE ON atlas_query_security_observation TO tenant_app;",
    "forbidden_grant"=>"GRANT ALL ON atlas_query_security_observation TO tenant_app;",
    "failed_row"=>'failed_row: "closure.definitive-domain.query.security.security"',
    "target"=>'target: "query.security"',
    "helper"=>'SecurityJsonOutput.parse_single_json_object!(',
    "final_cardinality"=>"atlas_query_security_observation final cardinality expected 1 row, got %",
    "row_count_guard"=>"atlas_query_security_observation refusal update expected 1 row, got %"
  },
  "query.sql-surface"=>{
    "body"=>sql_surface,
    "seed"=>"INSERT INTO atlas_sql_surface_observation DEFAULT VALUES;",
    "grant"=>"GRANT SELECT, UPDATE ON atlas_sql_surface_observation TO atlas_sql_surface_writer;",
    "forbidden_grant"=>"GRANT ALL ON atlas_sql_surface_observation TO atlas_sql_surface_writer;",
    "failed_row"=>'failed_row: "closure.definitive-domain.query.sql-surface.security"',
    "target"=>'target: "query.sql-surface"',
    "helper"=>'psql_json_execution_for_row!(',
    "final_cardinality"=>"atlas_sql_surface_observation final cardinality expected 1 row, got %",
    "row_count_guard"=>"atlas_sql_surface_observation refusal update expected 1 row, got %"
  },
  "query.types-constraints"=>{
    "body"=>types_constraints,
    "seed"=>"INSERT INTO atlas_typed_order_observation DEFAULT VALUES;",
    "grant"=>"GRANT SELECT, UPDATE ON atlas_typed_order_observation TO atlas_typed_order_writer;",
    "forbidden_grant"=>"GRANT ALL ON atlas_typed_order_observation TO atlas_typed_order_writer;",
    "failed_row"=>'failed_row: "closure.definitive-domain.query.types-constraints.security"',
    "target"=>'target: "query.types-constraints"',
    "helper"=>'psql_json_execution_for_row!(',
    "final_cardinality"=>"atlas_typed_order_observation final cardinality expected 1 row, got %",
    "row_count_guard"=>"atlas_typed_order_observation refusal update expected 1 row, got %"
  }
}.freeze

def refusal_block(body)
  anchor = "DO $atlas$\n    DECLARE observed_state text;\n    DECLARE updated_rows bigint;\n    BEGIN"
  start = body.index(anchor) or raise "refusal DO block missing"
  finish = body.index("    $atlas$;", start) or raise "refusal DO block terminator missing"
  body[start, finish - start + "    $atlas$;".length]
end

def verify_section!(name, section)
  body = section.fetch("body")
  raise "#{name} must seed exactly one observation row before tenant role" unless body.scan(section.fetch("seed")).length == 1 && body.index(section.fetch("seed")) < body.index("SET ROLE ")
  raise "#{name} must not allow tenant observation inserts" unless body.include?(section.fetch("grant")) && !body.include?(section.fetch("forbidden_grant"))
  raise "#{name} must terminate every DO block with END;" if body.include?("\n    END\n    $atlas$;")
  if name == "query.sql-surface"
    block = refusal_block(body)
    raise "#{name} must set tenant role before the visibility statement" unless body.include?("SET ROLE atlas_sql_surface_writer;")
    raise "#{name} must update visible_rows in a statement after RETURNING update" unless body.include?("      UPDATE atlas_sql_surface_observation\n      SET returned_id = (SELECT id FROM inserted),\n          returned_note = (SELECT note FROM inserted);") &&
      body.include?("      UPDATE atlas_sql_surface_observation\n      SET visible_rows = (SELECT count(*)::integer FROM atlas_sql_surface_secure WHERE tenant = 'atlas_sql_surface_writer');") &&
      body.index("      UPDATE atlas_sql_surface_observation\n      SET returned_id = (SELECT id FROM inserted),\n          returned_note = (SELECT note FROM inserted);") <
      body.index("      UPDATE atlas_sql_surface_observation\n      SET visible_rows = (SELECT count(*)::integer FROM atlas_sql_surface_secure WHERE tenant = 'atlas_sql_surface_writer');")
    raise "#{name} outer BEGIN must directly contain the first nested BEGIN refusal block" unless block.include?("DO $atlas$\n    DECLARE observed_state text;\n    DECLARE updated_rows bigint;\n    BEGIN\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 1, 100, 'duplicate');")
    raise "#{name} must keep exactly three sibling nested refusal blocks inside the outer DO block" unless block.scan(/\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure\(/).length == 3
    raise "#{name} must keep sibling refusal/check blocks inside the outer DO block" unless block.include?("      END;\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 2, -1, 'invalid');") && block.include?("      END;\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('postgres', 2, 100, 'escape');")
    raise "#{name} must keep exactly six row-count guards" unless body.scan("GET DIAGNOSTICS updated_rows = ROW_COUNT;").length == 6
  end
  if name == "query.types-constraints"
    block = refusal_block(body)
    raise "#{name} outer BEGIN must directly contain the first nested BEGIN refusal block" unless block.include?("DO $atlas$\n    DECLARE observed_state text;\n    DECLARE updated_rows bigint;\n    BEGIN\n      BEGIN\n        INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)")
    raise "#{name} must keep exactly two sibling nested refusal blocks inside the outer DO block" unless block.scan(/\n      BEGIN\n        INSERT INTO atlas_typed_order_secure\(/).length == 2
    raise "#{name} must keep sibling refusal blocks inside the outer DO block" unless block.include?("      END;\n      BEGIN\n        INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)\n        VALUES ('postgres', 'confirmed', 1, ARRAY['escape'], '{\"name\":\"escape\"}', tstzrange('2026-01-01', '2026-01-02'), datemultirange(daterange('2026-01-01', '2026-01-02', '[)')), '192.0.2.20/24');")
    raise "#{name} must keep exactly four row-count guards" unless body.scan("GET DIAGNOSTICS updated_rows = ROW_COUNT;").length == 4
  end
  raise "#{name} must keep final observation cardinality guard" unless body.include?(section.fetch("final_cardinality"))
  raise "#{name} must keep row-count guard" unless body.include?(section.fetch("row_count_guard")) && body.include?("GET DIAGNOSTICS updated_rows = ROW_COUNT;")
  raise "#{name} must keep row-specific failure binding" unless body.include?(section.fetch("failed_row")) && body.include?(section.fetch("target")) && body.include?(section.fetch("helper"))
end

SECTIONS.each do |name, config|
  verify_section!(name, config)
end

begin
  verify_section!("query.partitioning", SECTIONS.fetch("query.partitioning").merge("body"=>partitioning.sub("    END;\n    $atlas$;", "    END\n    $atlas$;")))
  abort "query.partitioning DO semicolon regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("terminate every DO block")
end

begin
  verify_section!("query.sql-surface", SECTIONS.fetch("query.sql-surface").merge("body"=>sql_surface.sub("    INSERT INTO atlas_sql_surface_observation DEFAULT VALUES;\n", "")))
  abort "query.sql-surface missing observation seed regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("seed exactly one observation row")
end

begin
  verify_section!("query.types-constraints", SECTIONS.fetch("query.types-constraints").merge("body"=>types_constraints.sub("GRANT SELECT, UPDATE ON atlas_typed_order_observation TO atlas_typed_order_writer;", "GRANT ALL ON atlas_typed_order_observation TO atlas_typed_order_writer;")))
  abort "query.types-constraints tenant observation insert regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("must not allow tenant observation inserts")
end

begin
  verify_section!("query.sql-surface", SECTIONS.fetch("query.sql-surface").merge("body"=>sql_surface.sub("psql_json_execution_for_row!(", "psql_json_execution(")))
  abort "query.sql-surface generic unknown mapping regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("row-specific failure binding")
end

begin
  verify_section!("query.sql-surface", SECTIONS.fetch("query.sql-surface").merge("body"=>sql_surface.sub("      UPDATE atlas_sql_surface_observation\n      SET returned_id = (SELECT id FROM inserted),\n          returned_note = (SELECT note FROM inserted);\n      GET DIAGNOSTICS updated_rows = ROW_COUNT;\n      IF updated_rows <> 1 THEN\n        RAISE EXCEPTION 'atlas_sql_surface_observation insert/update expected 1 row, got %', updated_rows;\n      END IF;\n      UPDATE atlas_sql_surface_observation\n      SET visible_rows = (SELECT count(*)::integer FROM atlas_sql_surface_secure WHERE tenant = 'atlas_sql_surface_writer');\n      GET DIAGNOSTICS updated_rows = ROW_COUNT;\n      IF updated_rows <> 1 THEN\n        RAISE EXCEPTION 'atlas_sql_surface_observation visible_rows update expected 1 row, got %', updated_rows;\n      END IF;\n", "      UPDATE atlas_sql_surface_observation\n      SET returned_id = (SELECT id FROM inserted),\n          returned_note = (SELECT note FROM inserted),\n          visible_rows = (SELECT count(*)::integer FROM atlas_sql_surface_secure WHERE tenant = 'atlas_sql_surface_writer');\n      GET DIAGNOSTICS updated_rows = ROW_COUNT;\n      IF updated_rows <> 1 THEN\n        RAISE EXCEPTION 'atlas_sql_surface_observation insert/update expected 1 row, got %', updated_rows;\n      END IF;\n")))
  abort "query.sql-surface same-statement visibility snapshot regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("visible_rows in a statement after RETURNING update")
end

begin
  verify_section!("query.sql-surface", SECTIONS.fetch("query.sql-surface").merge("body"=>sql_surface.sub("    BEGIN\n      BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 1, 100, 'duplicate');", "    BEGIN\n        INSERT INTO atlas_sql_surface_secure(tenant, id, amount, note) VALUES ('atlas_sql_surface_writer', 1, 100, 'duplicate');")))
  abort "query.sql-surface first nested BEGIN regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("outer BEGIN must directly contain the first nested BEGIN")
end

begin
  verify_section!("query.types-constraints", SECTIONS.fetch("query.types-constraints").merge("body"=>types_constraints.sub("      END;\n      BEGIN\n        INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)\n        VALUES ('postgres', 'confirmed', 1, ARRAY['escape'], '{\"name\":\"escape\"}', tstzrange('2026-01-01', '2026-01-02'), datemultirange(daterange('2026-01-01', '2026-01-02', '[)')), '192.0.2.20/24');", "    END;\n    BEGIN\n      INSERT INTO atlas_typed_order_secure(tenant, status, amount, tags, metadata, valid_during, service_days, client_network)\n      VALUES ('postgres', 'confirmed', 1, ARRAY['escape'], '{\"name\":\"escape\"}', tstzrange('2026-01-01', '2026-01-02'), datemultirange(daterange('2026-01-01', '2026-01-02', '[)')), '192.0.2.20/24');")))
  abort "query.types-constraints sibling refusal block escaped outer DO regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("sibling refusal blocks inside the outer DO block") || e.message.include?("exactly two sibling nested refusal blocks")
end

begin
  verify_section!("query.types-constraints", SECTIONS.fetch("query.types-constraints").merge("body"=>types_constraints.sub("atlas_typed_order_observation final cardinality expected 1 row, got %", "atlas_typed_order_observation final cardinality removed")))
  abort "query.types-constraints final cardinality regression was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("final observation cardinality")
end

puts "Next security tranche runtime hygieneを検証しました: exact4 executors keep seeded observations, separate visible_rows statement, nested sibling PL/pgSQL refusal blocks, END; termination, SELECT/UPDATE-only grants, and row-specific structured failure mapping"
