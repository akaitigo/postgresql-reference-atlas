# frozen_string_literal: true

require "json"

module SecurityPublicationProvenanceContract
  CONTRACT = {
    "pattern_id"=>"definitive-domain.publication.provenance",
    "target_id"=>"publication.provenance",
    "executor_id"=>"publication-provenance-security",
    "command"=>"ruby tools/run-scenario-security-001.rb",
    "runtime_kind"=>"local-static-verifier",
    "shell_fragments"=>[
      'ledger_time="${EVIDENCE_LEDGER_TIME:-}"',
      'required=(',
      'LICENSE',
      'NOTICE',
      'SECURITY.md',
      'CONTRIBUTING.md',
      'third_party/manifest.yaml',
      'sbom.spdx.json',
      'surface/sql-commands.yaml',
      "rg -n --hidden",
      "jq -e '.spdxVersion == \"SPDX-2.3\" and .packages[0].licenseDeclared == \"Apache-2.0\"'",
      'record_evidence foundation-authority-lock',
      'record_evidence publication-static-gates publication.provenance',
      'ruby "$ROOT/scripts/graph-gates.rb"'
    ],
    "required_result_fields"=>%w[
      authority_lock_digest rights_files secret_scan sbom third_party_manifest verdict
    ],
    "required_oracle_predicates"=>%w[
      ledger_time_bound
      required_rights_files_present
      authority_lock_digest_matches_coverage
      third_party_manifest_present
      apache_license_declared
      spdx_apache_declared
      secret_scan_pass
      record_evidence_bound
      graph_gate_invoked
    ],
    "negative_cases"=>%w[
      missing_required_rights_file
      authority_lock_digest_mismatch
      sbom_license_drift
      third_party_manifest_missing
      secret_scan_leak_detected
      static_gate_noop_regression
    ],
    "diagnostic_fields"=>%w[
      actual_result oracle_predicates shell_fragments bindings canonical_artifacts
    ]
  }.freeze

  module_function

  def contract
    JSON.parse(JSON.generate(CONTRACT))
  end

  def verify!(candidate = contract)
    raise "publication.provenance contract pattern drifted" unless candidate.fetch("pattern_id") == CONTRACT.fetch("pattern_id")
    raise "publication.provenance contract target drifted" unless candidate.fetch("target_id") == CONTRACT.fetch("target_id")
    raise "publication.provenance contract executor drifted" unless candidate.fetch("executor_id") == CONTRACT.fetch("executor_id")
    raise "publication.provenance contract command drifted" unless candidate.fetch("command") == CONTRACT.fetch("command")
    raise "publication.provenance contract runtime drifted" unless candidate.fetch("runtime_kind") == CONTRACT.fetch("runtime_kind")
    raise "publication.provenance contract shell fragments drifted" unless candidate.fetch("shell_fragments") == CONTRACT.fetch("shell_fragments")
    raise "publication.provenance contract result fields drifted" unless candidate.fetch("required_result_fields") == CONTRACT.fetch("required_result_fields")
    raise "publication.provenance contract oracle predicates drifted" unless candidate.fetch("required_oracle_predicates") == CONTRACT.fetch("required_oracle_predicates")
    raise "publication.provenance contract negatives drifted" unless candidate.fetch("negative_cases") == CONTRACT.fetch("negative_cases")
    raise "publication.provenance contract diagnostic fields drifted" unless candidate.fetch("diagnostic_fields") == CONTRACT.fetch("diagnostic_fields")

    raise "publication.provenance contract shell fragments weakened" unless candidate.fetch("shell_fragments").length >= 12
    raise "publication.provenance contract negatives weakened" unless candidate.fetch("negative_cases").length >= 6
    raise "publication.provenance contract diagnostic fields weakened" unless candidate.fetch("diagnostic_fields").length >= 5
    raise "publication.provenance contract contains duplicate shell fragments" unless candidate.fetch("shell_fragments").uniq == candidate.fetch("shell_fragments")
    raise "publication.provenance contract contains duplicate negatives" unless candidate.fetch("negative_cases").uniq == candidate.fetch("negative_cases")
    true
  end
end
