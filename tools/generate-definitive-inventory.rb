#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "yaml"

root = File.expand_path("..", __dir__)
source_root = File.expand_path(ARGV.fetch(0))
runtime_capture = ARGV.fetch(1)
sources = YAML.safe_load(File.read(File.join(root, "sources.lock.yaml")), aliases: false)
  .fetch("sources").to_h { |source| [source.fetch("id"), source] }
source_lock = sources.fetch("postgresql-source-rel-18.6")
source_head, source_error, source_status = Open3.capture3("git", "-C", source_root, "rev-parse", "HEAD")
abort "Source checkoutを検証できません: #{source_error.strip}" unless source_status.success?
abort "Source commitがLockと一致しません: #{source_head.strip}" unless source_head.strip == source_lock.fetch("version")
coverage = YAML.safe_load(File.read(File.join(root, "coverage.yaml")), aliases: false)
targets = coverage.fetch("targets").to_h { |target| [target.fetch("id"), target] }
sql_inventory = YAML.safe_load(File.read(File.join(root, "surface/sql-commands.yaml")), aliases: false)
sql_ids = sql_inventory.fetch("commands").to_h { |command| [command.fetch("id"), command] }
output = File.join(root, "authority")
FileUtils.mkdir_p(output)

surface_map = {
  "runtime-type" => ["query.runtime-types", %w[foundations-mechanics implementation-construction testing-verification]],
  "runtime-function" => ["query.runtime-functions", %w[implementation-construction testing-verification]],
  "runtime-operator" => ["query.runtime-operators", %w[implementation-construction testing-verification performance-capacity-cost]],
  "runtime-cast" => ["query.runtime-casts", %w[foundations-mechanics testing-verification security-privacy-safety]],
  "system-catalog" => ["query.system-catalogs", %w[foundations-mechanics operations-observability compatibility-integration]],
  "guc" => ["operations.gucs", %w[operations-observability security-privacy-safety performance-capacity-cost]],
  "extension" => ["query.extension", %w[implementation-construction compatibility-integration provenance-rights]],
  "access-method" => ["performance.index-methods", %w[architecture-design performance-capacity-cost decision-comparison]],
  "collation" => ["query.runtime-types", %w[foundations-mechanics compatibility-integration migration-evolution-deprecation]]
}.freeze

target_set_surfaces = {
  "foundation"=>%w[orientation-scope foundations-mechanics testing-verification],
  "query"=>%w[foundations-mechanics implementation-construction testing-verification],
  "concurrency"=>%w[foundations-mechanics testing-verification failure-recovery],
  "performance"=>%w[architecture-design testing-verification performance-capacity-cost decision-comparison],
  "operations"=>%w[testing-verification failure-recovery operations-observability],
  "lifecycle"=>%w[testing-verification compatibility-integration migration-evolution-deprecation],
  "skill"=>%w[orientation-scope testing-verification agent-skill],
  "publication"=>%w[orientation-scope testing-verification provenance-rights]
}.freeze

runtime_surfaces = File.readlines(runtime_capture, chomp: true).reject(&:empty?).map do |line|
  item = JSON.parse(line)
  target_id, surface_ids = surface_map.fetch(item.fetch("domain"))
  id = "#{item.fetch("domain")}.#{item.fetch("key").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\z/, "")}"
  {
    "id" => id, "locator" => item.fetch("locator"), "kind" => "behavior",
    "capability_id" => target_id, "behavior_id" => id, "title" => item.fetch("title"), "surface_ids" => surface_ids
  }
end

source_surfaces = []
doc_map = YAML.safe_load(File.read(File.join(root, "surface/definitive-doc-map.yaml")), aliases: false)
abort "Doc MapのSourceがLockと一致しません" unless doc_map.fetch("source_id") == source_lock.fetch("id")
doc_file_targets = {}
doc_map.fetch("targets").each do |target_id, files|
  abort "Doc Mapが未知のTargetを参照しています: #{target_id}" unless targets.key?(target_id)
  files.each do |file|
    abort "Doc MapでFileが重複しています: #{file}" if doc_file_targets.key?(file)
    doc_file_targets[file] = target_id
  end
end
doc_files = Dir.glob(File.join(source_root, "doc/src/sgml/*.sgml")).sort
unclassified_doc_files = doc_files.map { |path| File.basename(path) } - doc_file_targets.keys
unknown_doc_files = doc_file_targets.keys - doc_files.map { |path| File.basename(path) }
abort "未分類の公式Doc Fileがあります: #{unclassified_doc_files.join(", ")}" unless unclassified_doc_files.empty?
abort "Lock Sourceに存在しないDoc Fileがあります: #{unknown_doc_files.join(", ")}" unless unknown_doc_files.empty?
doc_section_surfaces = doc_files.flat_map do |path|
  file = File.basename(path)
  target_id = doc_file_targets.fetch(file)
  surface_ids = target_set_surfaces.fetch(targets.fetch(target_id).fetch("target_set"))
  File.read(path, encoding: "UTF-8").scan(/\bid=["']([A-Za-z0-9_.:-]+)["']/).flatten.uniq.map do |section_id|
    id = "docs-section.#{File.basename(file, ".sgml").gsub(/[^a-z0-9]+/, "-")}.#{section_id.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\z/, "")}"
    {"id"=>id,"locator"=>"doc/src/sgml/#{file}##{section_id}","kind"=>"behavior","capability_id"=>target_id,"behavior_id"=>id,"title"=>"SGML section #{section_id.tr("-_.", "   ")}","surface_ids"=>surface_ids}
  end
end
docs_sql_surfaces = sql_inventory.fetch("commands").map do |command|
  id = "docs-sql.#{command.fetch("id")}"
  {"id"=>id,"locator"=>command.fetch("reference"),"kind"=>"capability","capability_id"=>"query.sql-commands","behavior_id"=>id,"title"=>command.fetch("title"),"surface_ids"=>%w[implementation-construction testing-verification compatibility-integration]}
end
Dir.glob(File.join(source_root, "doc/src/sgml/ref/*.sgml")).sort.each do |path|
  slug = File.basename(path, ".sgml").sub(/-ref\z/, "")
  command_slug = slug.tr("_", "-")
  text = File.read(path, encoding: "UTF-8")
  title = text[/<refname>(.*?)<\/refname>/mi, 1]&.gsub(/<[^>]+>/, "")&.strip || slug
  if sql_ids.key?(command_slug)
    target_id = "query.sql-commands"
    surface_ids = %w[implementation-construction testing-verification compatibility-integration]
  else
    target_id = "integration.client-tools"
    surface_ids = %w[implementation-construction operations-observability compatibility-integration]
  end
  id = "source-ref.#{slug.gsub(/[^a-z0-9]+/, "-")}"
  source_surfaces << {"id"=>id,"locator"=>path.delete_prefix("#{source_root}/"),"kind"=>"capability","capability_id"=>target_id,"behavior_id"=>id,"title"=>title,"surface_ids"=>surface_ids}
end

protocol_text = File.read(File.join(source_root, "doc/src/sgml/protocol.sgml"), encoding: "UTF-8")
protocol_text.scan(/id="(protocol-[a-z0-9-]+)"/).flatten.uniq.sort.each do |protocol_id|
  next if protocol_id == "protocol"
  id = "protocol.#{protocol_id.delete_prefix("protocol-")}"
  source_surfaces << {"id"=>id,"locator"=>"doc/src/sgml/protocol.sgml##{protocol_id}","kind"=>"behavior","capability_id"=>"integration.protocol","behavior_id"=>id,"title"=>protocol_id.tr("-", " "),"surface_ids"=>%w[foundations-mechanics testing-verification security-privacy-safety compatibility-integration]}
end

Dir.glob(File.join(source_root, "contrib/*/*.control")).sort.each do |path|
  name = File.basename(path, ".control")
  id = "contrib.#{name.gsub(/[^a-z0-9]+/, "-")}"
  source_surfaces << {"id"=>id,"locator"=>path.delete_prefix("#{source_root}/"),"kind"=>"capability","capability_id"=>"query.extension","behavior_id"=>id,"title"=>name,"surface_ids"=>%w[implementation-construction compatibility-integration provenance-rights]}
end

domain_targets = targets.keys.sort
domain_surfaces = domain_targets.map do |target_id|
  abort "Coverage Targetがありません: #{target_id}" unless targets.key?(target_id)
  id = "definitive-domain.#{target_id}"
  {"id"=>id,"locator"=>"coverage.yaml##{target_id}","kind"=>"capability","capability_id"=>target_id,"behavior_id"=>id,"title"=>targets.fetch(target_id).fetch("title"),"surface_ids"=>%w[orientation-scope testing-verification]}
end

artifacts = [
  ["runtime-catalog", "postgres-container-18.6-alpine", runtime_surfaces],
  ["docs-sql", "postgresql-docs-18.6", docs_sql_surfaces],
  ["docs-sections", "postgresql-source-rel-18.6", doc_section_surfaces],
  ["source-surface", "postgresql-source-rel-18.6", source_surfaces],
  ["definitive-domain", "postgresql-docs-18.6", domain_surfaces]
].map do |id, source_id, surfaces|
  document = {
    "schema_version"=>2,"source_id"=>source_id,"source_digest"=>sources.fetch(source_id).fetch("digest"),
    "extraction"=>{"method"=>"machine-readable-primary","tool"=>"tools/generate-definitive-inventory.rb","reviewed_by"=>"independent-definitive-audit","reviewed_at"=>"2026-08-28"},
    "surfaces"=>surfaces
  }
  relative = "authority/#{id}.authority-surfaces.json"
  File.write(File.join(root, relative), JSON.pretty_generate(document) + "\n")
  [id, source_id, relative, surfaces]
end

claim_sources = {
  "integration.protocol"=>["postgresql-source-rel-18.6","postgresql-docs-18.6"],
  "integration.client-tools"=>["postgresql-source-rel-18.6","postgresql-docs-18.6"]
}
FileUtils.mkdir_p(File.join(root, "gaps/claims"))
artifacts.flat_map(&:last).map { |item| item.fetch("capability_id") }.uniq.each do |target_id|
  accepted_claim_path = File.join(root, "claims/#{target_id}.claim.yaml")
  proposal_path = File.join(root, "gaps/claims/#{target_id}.claim.yaml")
  next if File.exist?(accepted_claim_path) || File.exist?(proposal_path)
  source_ids = claim_sources.fetch(target_id, ["postgresql-docs-18.6", "postgresql-source-rel-18.6"])
  claim = {
    "schema_version"=>1,"id"=>target_id,"atlas_id"=>"postgresql-reference-atlas","capability_id"=>target_id,
    "statement"=>"PostgreSQL 18.6の#{targets.fetch(target_id).fetch("title")}は公式Inventory全件とTarget別実行証拠が揃うまでDefinitiveとは判定しない。",
    "status"=>"proposed","source_ids"=>source_ids,
    "proof_obligations"=>[{"id"=>"#{target_id}.definitive","statement"=>"対象Surfaceの正常、境界、拒否、障害、回復を適用可能性とともに検証する。","acceptance_criteria"=>["Inventory未分類ゼロかつ適用可能な全ScenarioがTarget固有Evidenceへ接続されること。"]}]
  }
  File.write(proposal_path, claim.to_yaml(line_width: -1))
end

inventory_items = artifacts.flat_map do |artifact_id, _source_id, _relative, surfaces|
  surfaces.map do |surface|
    target_id = surface.fetch("capability_id")
    {
      "id"=>surface.fetch("id"),"authority_artifact_id"=>artifact_id,"authority_surface_id"=>surface.fetch("id"),
      "locator"=>surface.fetch("locator"),"kind"=>surface.fetch("kind"),"capability_id"=>target_id,"behavior_id"=>surface.fetch("behavior_id"),
      "target_id"=>target_id,
      "title"=>surface.fetch("title"),"surface_ids"=>surface.fetch("surface_ids"),"classification"=>"included",
      "rationale"=>"PostgreSQL 18.6の公式配布物またはRuntime Catalogに存在するためCore Product Surfaceとして分類する。",
      "claim_ids"=>[File.exist?(File.join(root, "claims/#{target_id}.claim.yaml")) || File.exist?(File.join(root, "gaps/claims/#{target_id}.claim.yaml")) ? target_id : targets.fetch(target_id).fetch("claim_ids").first]
    }
  end
end
inventory = {
  "schema_version"=>2,"atlas_id"=>"postgresql-reference-atlas","epoch"=>"2026-08-28","authority_lock_digest"=>coverage.fetch("authority_lock_digest"),
  "authority_artifacts"=>artifacts.map { |id, source_id, relative, _| {"id"=>id,"source_id"=>source_id,"path"=>relative,"digest"=>"sha256:#{Digest::SHA256.file(File.join(root, relative)).hexdigest}"} },
  "items"=>inventory_items
}
File.write(File.join(root, "surface.inventory.yaml"), JSON.parse(JSON.generate(inventory)).to_yaml(line_width: -1))
puts "Definitive Inventory: #{inventory_items.length} items, #{artifacts.length} authority artifacts, unclassified=0"
