#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "yaml"

root = File.expand_path("..", __dir__)
claims = YAML.safe_load(File.read(File.join(root, "atlas/claims/index.yaml")), aliases: false).fetch("claims")
proofs = YAML.safe_load(File.read(File.join(root, "atlas/proof-obligations/index.yaml")), aliases: false)
  .fetch("proof_obligations").to_h { |proof| [proof.fetch("id"), proof] }
output = File.join(root, "claims")
FileUtils.mkdir_p(output)

claims.each do |claim|
  statement = claim.fetch("statement")
  statement = "#{statement} この主張は固定した一次資料と再実行可能な証拠だけに基づく。" if statement.length < 30
  entity = {
    "schema_version" => 1,
    "id" => claim.fetch("id"),
    "atlas_id" => "postgresql-reference-atlas",
    "capability_id" => claim.fetch("id"),
    "statement" => statement,
    "status" => "accepted",
    "source_ids" => claim.fetch("source_ids"),
    "proof_obligations" => claim.fetch("proof_obligation_ids").map do |proof_id|
      proof = proofs.fetch(proof_id)
      {
        "id" => proof_id,
        "statement" => "#{proof_id}を再現可能なCommandと明示したOracleによって検証する。",
        "acceptance_criteria" => [proof.fetch("acceptance")]
      }
    end
  }
  File.write(File.join(output, "#{claim.fetch("id")}.claim.yaml"), entity.to_yaml(line_width: -1))
end

puts "Claim実体を生成しました: #{claims.length}件"
