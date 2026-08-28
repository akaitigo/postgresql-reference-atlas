#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

root = File.expand_path("..", __dir__)
inventory_path = File.join(root, "surface/sql-commands.yaml")
inventory = YAML.safe_load(File.read(inventory_path), aliases: false)
commands = inventory.fetch("commands")
abort "SQL Command Inventoryが空です" if commands.empty?
ids = commands.map { |command| command.fetch("id") }
abort "SQL Command IDが重複しています" unless ids.uniq.length == ids.length
abort "SQL Commandに未割当があります" unless commands.all? { |command| command.fetch("capability_id") == "query.sql-surface" && command.fetch("coverage") == "covered" }

required_evidence = %w[lab.sql lab.types-constraints lab.catalog-inventory lab.security lab.partitioning lab.extension]
evidence = required_evidence.to_h do |id|
  path = File.join(root, "evidence", "#{id.delete_prefix("lab.")}.evidence.yaml")
  record = YAML.safe_load(File.read(path), aliases: false)
  abort "#{id}がpassではありません" unless record.fetch("id") == id && record.fetch("verdict") == "pass"
  [id, record.dig("artifact", "digest")]
end

result = {
  source_url: inventory.fetch("source_url"),
  source_version: inventory.fetch("source_version"),
  command_count: commands.length,
  command_ids_digest: "sha256:#{Digest::SHA256.hexdigest(ids.join("\n"))}",
  assigned_count: commands.count { |command| command.fetch("coverage") == "covered" },
  semantic_evidence: evidence,
  uncovered: [],
  verdict: "pass"
}
File.write(ARGV.fetch(0), JSON.pretty_generate(result) + "\n")
