#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"

ROOT = File.expand_path("..", __dir__)

coverage = YAML.safe_load(File.read(File.join(ROOT, "coverage.yaml")), aliases: false)
gap_claim = YAML.safe_load(File.read(File.join(ROOT, "gaps/claims/query.sql-commands.claim.yaml")), aliases: false)
definitive_report = JSON.parse(File.read(File.join(ROOT, "evidence/definitive-audit-report.json")))
makefile = File.read(File.join(ROOT, "Makefile"))

target = coverage.fetch("targets").find { |row| row.fetch("id") == "query.sql-commands" } or abort("query.sql-commands target missing")
abort "query.sql-commands target must stay required" unless target.fetch("requirement") == "required"
abort "query.sql-commands target must stay partial" unless target.fetch("state") == "partial"
abort "query.sql-commands target claim binding drifted" unless target.fetch("claim_ids") == ["query.sql-surface"]

abort "query.sql-commands gap claim id drifted" unless gap_claim.fetch("id") == "query.sql-commands"
abort "query.sql-commands gap claim must stay proposed" unless gap_claim.fetch("status") == "proposed"
abort "query.sql-commands proof obligation drifted" unless gap_claim.fetch("proof_obligations").map { |item| item.fetch("id") } == ["query.sql-commands.definitive"]

target_gap = definitive_report.dig("verification", "target_gaps").find { |row| row.fetch("target_id") == "query.sql-commands" } or abort("query.sql-commands definitive target gap missing")
abort "query.sql-commands definitive target gap must stay partial" unless target_gap.fetch("state") == "partial"
abort "query.sql-commands missing scenario denominator drifted" unless target_gap.fetch("missing_scenarios") == %w[normal boundary rejection]

target_state = definitive_report.dig("skill", "target_states").find { |row| row.fetch("id") == "query.sql-commands" } or abort("query.sql-commands skill target state missing")
abort "query.sql-commands skill target state must stay partial" unless target_state.fetch("state") == "partial"

abort "incomplete definitive promotion guard missing" unless makefile.include?("incomplete repository unexpectedly passed Definitive promotion")

puts "query.sql-commands partial contractを検証しました: required+partial state, proposed gap claim, definitive gap, and promotion block are fixed"
