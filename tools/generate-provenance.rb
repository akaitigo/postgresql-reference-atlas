#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"

root = File.expand_path("..", __dir__)
claims = YAML.safe_load(File.read(File.join(root, "atlas/claims/index.yaml")), aliases: false)
  .fetch("claims").to_h { |claim| [claim.fetch("id"), claim] }
records = Dir.glob(File.join(root, "evidence", "*.evidence.yaml")).sort.map do |path|
  evidence = YAML.safe_load(File.read(path), aliases: false)
  artifact_path = evidence.dig("artifact", "uri")
  source_ids = evidence.fetch("claim_ids").flat_map { |claim_id| claims.fetch(claim_id).fetch("source_ids") }.uniq.sort
  kind = case evidence.fetch("kind")
         when "skill-eval" then "skill-eval"
         when "benchmark", "measurement" then "benchmark"
         when "capture", "trace", "log" then "capture"
         else "test-report"
         end
  {
    "path" => artifact_path,
    "digest" => "sha256:#{Digest::SHA256.file(File.join(root, artifact_path)).hexdigest}",
    "kind" => kind,
    "license" => "Apache-2.0",
    "source_ids" => source_ids,
    "generated_by" => evidence.fetch("command")
  }
end

{
  "evals/postgresql-router.skill-eval.json" => ["skill-eval", ["postgresql-docs-18.6"], "make eval"],
  "sbom.spdx.json" => ["sbom", ["postgresql-source-rel-18.6"], "make provenance"],
  "authority/FE_DEPTH_REFERENCE.json" => ["document", [], "frontend-behavior-atlas@4a0b2df8e2091a963bd0e0e1bbccef9c84b49a45"],
  "authority/locator-extraction.snapshot.json" => ["generated", ["postgresql-docs-18.6", "postgresql-source-rel-18.6"], "ruby tools/generate-authority-locators.rb <REL_18_6-checkout>"],
  "authority/locator-draft/definitive-domain.json" => ["generated", [], "ruby tools/generate-authority-locators.rb <REL_18_6-checkout>"],
  "authority/locator-draft/docs-sections.json" => ["generated", ["postgresql-source-rel-18.6"], "ruby tools/generate-authority-locators.rb <REL_18_6-checkout>"],
  "authority/locator-draft/docs-sql.json" => ["generated", ["postgresql-docs-18.6", "postgresql-source-rel-18.6"], "ruby tools/generate-authority-locators.rb <REL_18_6-checkout>"],
  "authority/locator-draft/runtime-catalog.json" => ["generated", ["postgres-container-18.6-alpine"], "ruby tools/generate-authority-locators.rb <REL_18_6-checkout>"],
  "authority/locator-draft/source-surface.json" => ["generated", ["postgresql-source-rel-18.6"], "ruby tools/generate-authority-locators.rb <REL_18_6-checkout>"],
  "postgresql-depth-parity.yaml" => ["generated", [], "make depth-parity-audit"]
}.each do |relative, (kind, source_ids, generator)|
  records << {
    "path" => relative,
    "digest" => "sha256:#{Digest::SHA256.file(File.join(root, relative)).hexdigest}",
    "kind" => kind,
    "license" => "Apache-2.0",
    "source_ids" => source_ids,
    "generated_by" => generator
  }
end

records << {
  "path" => "authority/extraction.snapshot.json",
  "digest" => "sha256:#{Digest::SHA256.file(File.join(root, "authority/extraction.snapshot.json")).hexdigest}",
  "kind" => "generated",
  "license" => "Apache-2.0",
  "source_ids" => [],
  "generated_by" => "ruby tools/generate-core-authority-extraction.rb"
}
Dir.glob(File.join(root, "authority/surfaces-draft/*.json")).sort.each do |path|
  source_id = File.basename(path, ".json")
  records << {
    "path" => path.delete_prefix("#{root}/"),
    "digest" => "sha256:#{Digest::SHA256.file(path).hexdigest}",
    "kind" => "generated",
    "license" => "Apache-2.0",
    "source_ids" => [source_id],
    "generated_by" => "ruby tools/generate-core-authority-extraction.rb"
  }
end

document = {
  "schema_version" => 1,
  "atlas_id" => "postgresql-reference-atlas",
  "generated_at" => Time.now.utc.iso8601,
  "artifacts" => records.sort_by { |record| record.fetch("path") }
}
File.write(File.join(root, "provenance.yaml"), document.to_yaml(line_width: -1))
puts "Provenanceを生成しました: #{records.length} Artifact"
