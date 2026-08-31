#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../tools/lib/security_publication_provenance_contract"

contract = SecurityPublicationProvenanceContract.contract
SecurityPublicationProvenanceContract.verify!(contract)

tranche_source = File.read(File.expand_path("../tools/lib/security_published_tranche_contract.rb", __dir__))
abort "published tranche contract must reference publication.provenance executor" unless tranche_source.include?('"executor_id"=>"publication-provenance-security"')
abort "published tranche contract must bind publication.provenance contract support path" unless tranche_source.include?('"tools/lib/security_publication_provenance_contract.rb"')

static_gates = File.read(File.expand_path("../scripts/static-gates.sh", __dir__))
SecurityPublicationProvenanceContract::CONTRACT.fetch("shell_fragments").each do |fragment|
  abort "publication.provenance shell fragment missing from static-gates: #{fragment}" unless static_gates.include?(fragment)
end

deleted_fragment = SecurityPublicationProvenanceContract.contract
deleted_fragment.fetch("shell_fragments").delete('record_evidence publication-static-gates publication.provenance')
begin
  SecurityPublicationProvenanceContract.verify!(deleted_fragment)
  abort "deleted publication provenance shell fragment was accepted"
rescue RuntimeError => e
  raise unless e.message.include?("shell fragments drifted")
end

weakened_predicates = SecurityPublicationProvenanceContract.contract
weakened_predicates.fetch("required_oracle_predicates").delete("graph_gate_invoked")
begin
  SecurityPublicationProvenanceContract.verify!(weakened_predicates)
  abort "weakened publication provenance oracle predicates were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("oracle predicates drifted")
end

weakened_negative = SecurityPublicationProvenanceContract.contract
weakened_negative.fetch("negative_cases").delete("static_gate_noop_regression")
begin
  SecurityPublicationProvenanceContract.verify!(weakened_negative)
  abort "weakened publication provenance negatives were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("negatives drifted")
end

weakened_diagnostic = SecurityPublicationProvenanceContract.contract
weakened_diagnostic.fetch("diagnostic_fields").delete("canonical_artifacts")
begin
  SecurityPublicationProvenanceContract.verify!(weakened_diagnostic)
  abort "weakened publication provenance diagnostic fields were accepted"
rescue RuntimeError => e
  raise unless e.message.include?("diagnostic fields drifted")
end

rights_guard_removed = static_gates.sub(%r{^\s*third_party/manifest\.yaml\s*$}, "      THIRD_PARTY_MANIFEST_REMOVED")
abort "publication provenance test fixture failed to remove required rights file guard" if rights_guard_removed == static_gates
missing_rights_guard = SecurityPublicationProvenanceContract::CONTRACT.fetch("shell_fragments").reject do |fragment|
  rights_guard_removed.include?(fragment)
end
abort "required rights file guard regression went undetected" unless missing_rights_guard == ["third_party/manifest.yaml"]

puts "publication.provenance security contractを検証しました: static gate shell/oracle/negative/diagnostic guards are fixed"
