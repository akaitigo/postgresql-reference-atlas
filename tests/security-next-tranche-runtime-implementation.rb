#!/usr/bin/env ruby
# frozen_string_literal: true

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))
oracle_source = File.read(File.expand_path("../tools/lib/security_scenario_oracles.rb", __dir__))

def section(source, name, next_name = nil)
  if next_name
    source[/def #{Regexp.escape(name)}\(container\)(.*?)^def #{Regexp.escape(next_name)}\(container\)/m, 1]
  else
    source[/def #{Regexp.escape(name)}\(container\)(.*?)^end$/m, 1]
  end
end

{
  "definitive-domain.query.partitioning"=>"query-partitioning-security",
  "definitive-domain.query.security"=>"query-security",
  "definitive-domain.query.sql-surface"=>"query-sql-surface-security",
  "definitive-domain.query.types-constraints"=>"query-types-constraints-security"
}.each do |pattern_id, executor_id|
  abort "pattern #{pattern_id} missing from security runner" unless source.include?(%("#{pattern_id}"=>{))
  abort "pattern #{pattern_id} executor drifted" unless source.include?(%("executor"=>"#{executor_id}"))
end

abort "partitioning oracle helper missing" unless oracle_source.include?("def query_partitioning_predicates(result, marker:)")
abort "query.security oracle helper missing" unless oracle_source.include?("def query_security_predicates(result, marker:)")
abort "query.sql-surface oracle helper missing" unless oracle_source.include?("def query_sql_surface_predicates(result, marker:)")
abort "query.types-constraints oracle helper missing" unless oracle_source.include?("def query_types_constraints_predicates(result, marker:)")

partitioning = section(source, "query_partitioning_security_execution", "query_security_security_execution") or abort("query.partitioning runtime section missing")
query_security = section(source, "query_security_security_execution", "query_sql_surface_security_execution") or abort("query.security runtime section missing")
sql_surface = section(source, "query_sql_surface_security_execution", "query_types_constraints_security_execution") or abort("query.sql-surface runtime section missing")
types_constraints = section(source, "query_types_constraints_security_execution") or abort("query.types-constraints runtime section missing")

[
  [partitioning, "query_partitioning_predicates", "closure.definitive-domain.query.partitioning.security", "query.partitioning", "query.partitioning security Oracle failed"],
  [query_security, "query_security_predicates", "closure.definitive-domain.query.security.security", "query.security", "query.security security Oracle failed"],
  [sql_surface, "query_sql_surface_predicates", "closure.definitive-domain.query.sql-surface.security", "query.sql-surface", "query.sql-surface security Oracle failed"],
  [types_constraints, "query_types_constraints_predicates", "closure.definitive-domain.query.types-constraints.security", "query.types-constraints", "query.types-constraints security Oracle failed"]
].each do |body, predicate_name, failed_row, target, error|
  abort "#{target} runtime section does not compute structured predicates" unless body.include?("predicates = SecurityScenarioOracles.#{predicate_name}(result, marker: marker)")
  abort "#{target} runtime section does not raise structured failure" unless body.include?("SecurityFailureDiagnostics::ScenarioOracleFailure.new(")
  abort "#{target} failed_row binding drifted" unless body.include?(%Q(failed_row: "#{failed_row}"))
  abort "#{target} target binding drifted" unless body.include?(%Q(target: "#{target}"))
  abort "#{target} oracle_error binding drifted" unless body.include?(%Q(oracle_error: "#{error}"))
  abort "#{target} actual_result binding drifted" unless body.include?("actual_result: result")
  abort "#{target} oracle_predicates binding drifted" unless body.include?("oracle_predicates: predicates")
end

abort "query.partitioning runtime must enforce atomic publish support paths" unless source.include?('require_relative "lib/atomic_evidence_publisher"')
abort "query security runtime must enforce append-only diagnostics support" unless source.include?('require_relative "lib/security_failure_diagnostics"')
abort "query security runtime must bind JSON output helper" unless source.include?('require_relative "lib/security_json_output"')
abort "next exact4 runtimes must use row-specific command and JSON failure helper" unless partitioning.include?("psql_json_execution_for_row!(") && sql_surface.include?("psql_json_execution_for_row!(") && types_constraints.include?("psql_json_execution_for_row!(")
abort "query security runtime must use loopback dblink auth target" unless query_security.include?("host=127.0.0.1 dbname=atlas user=tenant_app password=tenant-atlas")
abort "query security runtime must verify the first matching host pg_hba rule as scram-sha-256, not any-host bool_or" unless query_security.include?("SELECT auth_method = 'scram-sha-256'") && query_security.include?("ORDER BY line_number") && !query_security.include?("bool_or(auth_method = 'scram-sha-256')")
abort "security runner must evaluate a same-run runtime preflight artifact" unless source.include?("runtime_preflight = SecurityRuntimeReadinessContract.evaluate_live_preflight!(plan: plan)")
abort "security runner must verify runnable state against the captured runtime preflight artifact" unless source.include?("SecurityRuntimeReadinessContract.verify_runnable!(plan: plan, preflight: runtime_preflight)")
abort "security runner must publish runtime preflight inside the canonical report environment" unless source.include?('report_environment = environment.merge("runtime_preflight"=>runtime_preflight)') && source.include?('"environment"=>report_environment')

puts "Next security tranche runtime implementationを検証しました: 4 patterns, 4 structured oracles, exact4 row-specific command/JSON failure helpers, same-run runtime preflight, and append-only failure bindings are fixed"
