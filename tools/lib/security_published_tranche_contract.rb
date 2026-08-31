# frozen_string_literal: true

require "json"
require "yaml"
require_relative "security_query_catalog_inventory_contract"
require_relative "security_query_extension_contract"
require_relative "security_performance_statistics_contract"
require_relative "security_publication_provenance_contract"
require_relative "security_scenario_tranche"

module SecurityPublishedTrancheContract
  ROOT = File.expand_path("../..", __dir__)
  COMMAND = "ruby tools/run-scenario-security-001.rb"
  ATTEMPT_POLICY = {
    "workers"=>1,
    "retries"=>0,
    "first_attempt_only"=>true
  }.freeze
  PUBLICATION_POLICY = {
    "publish_on"=>"full-run-passed",
    "failed_run"=>"retain-prior-success",
    "swap"=>"staged-directory-rename-with-rollback"
  }.freeze
  DIAGNOSTIC_POLICY = {
    "output_root"=>"artifacts/pattern-scenario-failures",
    "append_only"=>true,
    "preserve_original_error"=>true,
    "canonical_pre_post_unchanged_required"=>true
  }.freeze
  ROW_CONTRACTS = [
    {
      "pattern_id"=>"definitive-domain.performance.statistics",
      "target_id"=>"performance.statistics",
      "claim_id"=>"performance.statistics",
      "proof_obligation_id"=>"performance.extended-statistics",
      "executor_id"=>"performance-statistics-security",
      "runtime_kind"=>"postgresql-18.6-container",
      "oracle_id"=>"extended-statistics-estimate-window-and-owner-boundary",
      "support_paths"=>[
        "claims/performance.statistics.claim.yaml",
        "labs/statistics/verify.sql",
        "tools/lib/security_performance_statistics_contract.rb",
        "tools/run-scenario-security-001.rb"
      ],
      "required_result_fields"=>%w[
        server_version statistics_kinds estimated_rows actual_rows security_rejected
      ],
      "negative_cases"=>%w[
        estimated_rows_outside_80_120
        actual_rows_not_100
        missing_dependencies_or_mcv_statistics
        unauthorized_create_statistics_allowed
        unauthorized_analyze_allowed
        forced_planner_guc_present
      ],
      "command"=>COMMAND
    },
    {
      "pattern_id"=>"definitive-domain.publication.provenance",
      "target_id"=>"publication.provenance",
      "claim_id"=>"publication.provenance",
      "proof_obligation_id"=>"publication.static-gates",
      "executor_id"=>"publication-provenance-security",
      "runtime_kind"=>"local-static-verifier",
      "oracle_id"=>"rights-sbom-third-party-and-secret-scan-boundary",
      "support_paths"=>[
        "claims/publication.provenance.claim.yaml",
        "scripts/static-gates.sh",
        "third_party/manifest.yaml",
        "sbom.spdx.json",
        "tools/lib/security_publication_provenance_contract.rb",
        "tools/run-scenario-security-001.rb"
      ],
      "required_result_fields"=>%w[
        authority_lock_digest rights_files secret_scan sbom third_party_manifest
      ],
      "negative_cases"=>%w[
        missing_required_rights_file
        sbom_license_drift
        third_party_manifest_missing
        secret_scan_leak_detected
        static_gate_noop_regression
      ],
      "command"=>COMMAND
    },
    {
      "pattern_id"=>"definitive-domain.query.catalog-inventory",
      "target_id"=>"query.catalog-inventory",
      "claim_id"=>"query.catalog-inventory",
      "proof_obligation_id"=>"query.runtime-catalog-inventory",
      "executor_id"=>"catalog-inventory-security",
      "runtime_kind"=>"postgresql-18.6-container",
      "oracle_id"=>"catalog-digest-surface-with-read-only-role-boundary",
      "support_paths"=>[
        "claims/query.catalog-inventory.claim.yaml",
        "labs/catalog-inventory/verify.sql",
        "tools/lib/security_query_catalog_inventory_contract.rb",
        "tools/run-scenario-security-001.rb"
      ],
      "required_result_fields"=>%w[
        server_version
        types functions operators casts access_methods collations
        available_extensions catalog_relations security_rejected
      ],
      "negative_cases"=>%w[
        catalog_digest_missing
        count_only_self_report
        non_pg_catalog_scope
        unordered_digest_capture
        unauthorized_catalog_mutation_allowed
      ],
      "command"=>COMMAND
    },
    {
      "pattern_id"=>"definitive-domain.query.extension",
      "target_id"=>"query.extension",
      "claim_id"=>"query.extension",
      "proof_obligation_id"=>"query.bundled-extension",
      "executor_id"=>"bundled-extension-security",
      "runtime_kind"=>"postgresql-18.6-container",
      "oracle_id"=>"pg-trgm-gin-plan-with-extension-install-boundary",
      "support_paths"=>[
        "claims/query.extension.claim.yaml",
        "labs/extension/verify.sql",
        "tools/lib/security_query_extension_contract.rb",
        "tools/run-scenario-security-001.rb"
      ],
      "required_result_fields"=>%w[
        server_version extension_version similarity matching_rows security_rejected plan
      ],
      "negative_cases"=>%w[
        pg_trgm_missing
        gin_index_missing
        matching_rows_not_one
        wrong_index_name
        unauthorized_extension_install_allowed
        forced_planner_guc_present
      ],
      "command"=>COMMAND
    }
  ].freeze

  module_function

  def contracts
    JSON.parse(JSON.generate(ROW_CONTRACTS))
  end

  def row_ids(contracts_arg = contracts)
    contracts_arg.map { |row| SecurityScenarioTranche.row_id_for(row.fetch("pattern_id")) }
  end

  def verify!(plan: SecurityScenarioTranche.load_plan, contracts: contracts(), verify_files: true)
    raise "published tranche contract cardinality drifted" unless contracts.length == SecurityScenarioTranche::PUBLISHED_TRANCHE_PATTERN_IDS.length
    raise "published tranche contract pattern order drifted" unless contracts.map { |row| row.fetch("pattern_id") } == SecurityScenarioTranche::PUBLISHED_TRANCHE_PATTERN_IDS
    raise "published tranche contract row_ids drifted" unless row_ids(contracts) == SecurityScenarioTranche.expected_published_row_ids

    completed_ids = plan.fetch("completed_rows").map { |row| SecurityScenarioTranche.row_id_for(row.fetch("pattern_id")) }
    raise "published tranche contract is not bound to completed suite" unless (row_ids(contracts) - completed_ids).empty?

    report = JSON.parse(File.read(File.join(ROOT, "artifacts/pattern-scenarios/results.json")))
    published_patterns = report.fetch("tests").map { |test| [test.fetch("pattern_id"), test.fetch("scenario")] }.uniq
    expected_patterns = contracts.map { |row| [row.fetch("pattern_id"), "security"] }
    raise "published tranche runtime rows are missing from canonical runtime report" unless (expected_patterns - published_patterns).empty?

    expected_rows = ROW_CONTRACTS.to_h { |row| [row.fetch("pattern_id"), row] }
    contracts.each do |row|
      verify_contract_row!(row, expected_rows.fetch(row.fetch("pattern_id")), verify_files: verify_files)
      verify_row_specific_contract!(row)
    end
    true
  end

  def verify_contract_row!(row, expected_row, verify_files:)
    required_keys = %w[
      pattern_id target_id claim_id proof_obligation_id executor_id runtime_kind
      command oracle_id support_paths required_result_fields negative_cases
    ]
    missing = required_keys.reject { |key| row.key?(key) }
    raise "published tranche contract missing keys: #{missing.join(', ')}" unless missing.empty?
    raise "published tranche contract target drifted for #{row.fetch('pattern_id')}" unless row.fetch("target_id") == row.fetch("pattern_id").delete_prefix("definitive-domain.")
    raise "published tranche contract support paths empty for #{row.fetch('pattern_id')}" if row.fetch("support_paths").empty?
    raise "published tranche contract result fields empty for #{row.fetch('pattern_id')}" if row.fetch("required_result_fields").empty?
    raise "published tranche contract negatives weakened for #{row.fetch('pattern_id')}" unless row.fetch("negative_cases").length >= 4
    raise "published tranche contract negatives duplicated for #{row.fetch('pattern_id')}" unless row.fetch("negative_cases").uniq == row.fetch("negative_cases")
    raise "published tranche contract command drifted for #{row.fetch('pattern_id')}" unless row.fetch("command") == COMMAND

    %w[claim_id proof_obligation_id executor_id runtime_kind oracle_id command].each do |field|
      raise "published tranche contract #{field} drifted for #{row.fetch('pattern_id')}" unless row.fetch(field) == expected_row.fetch(field)
    end
    %w[support_paths required_result_fields negative_cases].each do |field|
      raise "published tranche contract #{field} drifted for #{row.fetch('pattern_id')}" unless row.fetch(field) == expected_row.fetch(field)
    end

    return unless verify_files

    missing_paths = row.fetch("support_paths").reject { |path| File.file?(File.join(ROOT, path)) }
    raise "published tranche contract support path missing for #{row.fetch('pattern_id')}: #{missing_paths.join(', ')}" unless missing_paths.empty?
    claim = YAML.safe_load(File.read(File.join(ROOT, "claims/#{row.fetch('claim_id')}.claim.yaml")), aliases: false)
    raise "published tranche claim id drifted for #{row.fetch('pattern_id')}" unless claim.fetch("id") == row.fetch("claim_id")
  end

  def verify_row_specific_contract!(row)
    case row.fetch("pattern_id")
    when SecurityPerformanceStatisticsContract::CONTRACT.fetch("pattern_id")
      SecurityPerformanceStatisticsContract.verify!
    when SecurityPublicationProvenanceContract::CONTRACT.fetch("pattern_id")
      SecurityPublicationProvenanceContract.verify!
    when SecurityQueryCatalogInventoryContract::CONTRACT.fetch("pattern_id")
      SecurityQueryCatalogInventoryContract.verify!
    when SecurityQueryExtensionContract::CONTRACT.fetch("pattern_id")
      SecurityQueryExtensionContract.verify!
    end
  end
end
