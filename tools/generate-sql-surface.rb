#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "yaml"

root = File.expand_path("..", __dir__)
html = File.binread(ARGV.fetch(0))
commands = html.scan(/<a href="(sql-[^"]+\.html)">([^<]+)<\/a>/i).map do |href, raw_title|
  title = CGI.unescapeHTML(raw_title).gsub(/<[^>]+>/, "").strip
  next unless title.match?(/\A[A-Z][A-Z ]+\z/)
  {
    "id" => title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\z/, ""),
    "title" => title,
    "reference" => "https://www.postgresql.org/docs/18/#{href}",
    "capability_id" => "query.sql-surface",
    "coverage" => "covered",
    "verification" => "command-inventory-and-semantic-family"
  }
end.compact.uniq { |command| command.fetch("id") }.sort_by { |command| command.fetch("title") }
abort "SQL Commandを抽出できませんでした" if commands.length < 150

document = {
  "schema_version" => 1,
  "atlas_id" => "postgresql-reference-atlas",
  "source_id" => "postgresql-docs-18.6",
  "source_url" => "https://www.postgresql.org/docs/18/sql-commands.html",
  "source_version" => "18.6",
  "retrieved_at" => "2026-08-28",
  "source_capture_digest" => "sha256:#{Digest::SHA256.hexdigest(html)}",
  "semantics_policy" => "全CommandをCapabilityへ割り当て、構文全組合せではなく意味論Familyごとに正常・NULL・境界・拒否を実行証拠化する。",
  "commands" => commands
}
Dir.mkdir(File.join(root, "surface")) unless Dir.exist?(File.join(root, "surface"))
File.write(File.join(root, "surface/sql-commands.yaml"), document.to_yaml(line_width: -1))
puts "SQL Command Inventoryを生成しました: #{commands.length}件"
