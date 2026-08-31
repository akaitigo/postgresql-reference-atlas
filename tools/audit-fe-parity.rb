#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

root = File.expand_path("..", __dir__)
matrix = YAML.safe_load(File.read(File.join(root, "fe-parity.matrix.yaml")), aliases: false)
inventory = YAML.safe_load(File.read(File.join(root, "surface.inventory.yaml")), aliases: false)
verification = YAML.safe_load(File.read(File.join(root, "verification.matrix.yaml")), aliases: false)
definitive = YAML.safe_load(File.read(File.join(root, "definitive.yaml")), aliases: false)
definitive_audit = JSON.parse(File.read(File.join(root, "evidence/definitive-audit-report.json")))
evidence_records = Dir.glob(File.join(root, "evidence/*.evidence.yaml")).map do |path|
  item = YAML.safe_load(File.read(path), aliases: false)
  [item.fetch("id"), item]
end.to_h
inventory_by_target = inventory.fetch("items").group_by { |item| item.fetch("target_id") }
rows_by_behavior = verification.fetch("rows").group_by { |row| row.fetch("behavior_id") }
open_targets = definitive_audit.dig("verification", "target_gaps").map { |item| item.fetch("target_id") }

json_paths = lambda do |value, prefix = "", result = []|
  case value
  when Hash
    value.each { |key, child| json_paths.call(child, [prefix, key].reject(&:empty?).join("."), result) }
  when Array
    result << prefix unless value.empty?
    value.each_with_index { |child, index| json_paths.call(child, "#{prefix}.#{index}", result) }
  else
    result << prefix
  end
  result
end

domains = matrix.fetch("domains").map do |domain|
  target_ids = domain.fetch("target_ids")
  behaviors = target_ids.flat_map { |id| inventory_by_target.fetch(id, []) }.map { |item| item.fetch("behavior_id") }.uniq
  missing_rows = behaviors.sum { |behavior| 10 - rows_by_behavior.fetch(behavior, []).map { |row| row.fetch("scenario") }.uniq.length }
  evidence_errors = []
  artifact_paths = {}
  domain.fetch("evidence_ids").each do |id|
    record = evidence_records[id]
    unless record
      evidence_errors << "missing evidence #{id}"
      next
    end
    artifact = File.join(root, record.dig("artifact", "uri"))
    actual = File.file?(artifact) ? "sha256:#{Digest::SHA256.file(artifact).hexdigest}" : nil
    evidence_errors << "artifact digest #{id}" unless actual == record.dig("artifact", "digest")
    artifact_name = File.basename(artifact, ".json")
    artifact_paths[artifact_name] = File.file?(artifact) ? json_paths.call(JSON.parse(File.read(artifact))).uniq : []
  end
  signal_errors = domain.fetch("artifact_signals").reject do |signal|
    artifact, path = signal.split(":", 2)
    artifact_paths.fetch(artifact, []).any? { |actual| actual == path || actual.start_with?("#{path}.") }
  end
  axes = {
    "authority"=>behaviors.any?,
    "behavior-variant"=>!target_ids.any? { |id| open_targets.include?(id) } && missing_rows.zero?,
    "runtime"=>domain.fetch("evidence_ids").any? && evidence_errors.empty?,
    "artifact"=>signal_errors.empty? && domain.fetch("artifact_signals").any?,
    "failure-recovery"=>!domain.fetch("failure_recovery_required", false) || (!target_ids.any? { |id| open_targets.include?(id) } && missing_rows.zero?),
    "comparison"=>!domain.fetch("comparison_required", false) || definitive.fetch("comparisons").any?,
    "integration"=>!domain.fetch("integration_required", false) || definitive.fetch("reference_systems").any?,
    "skill"=>!domain.fetch("skill_required", false) || (definitive_audit.dig("skill", "missing_surfaces").empty? && definitive_audit.dig("skill", "unrouted_targets").empty?)
  }
  {"id"=>domain.fetch("id"),"behaviors"=>behaviors.length,"scenario_rows_missing"=>missing_rows,"evidence_ids"=>domain.fetch("evidence_ids"),"evidence_errors"=>evidence_errors,"missing_artifact_signals"=>signal_errors,"axes"=>axes,"gaps"=>axes.select { |_axis, passed| !passed }.keys}
end
report = {
  "schema_version"=>1,"atlas_id"=>matrix.fetch("atlas_id"),"baseline"=>matrix.fetch("baseline"),
  "domains"=>domains,"gap_domains"=>domains.count { |domain| domain.fetch("gaps").any? },
  "gap_axes"=>domains.flat_map { |domain| domain.fetch("gaps").map { |axis| "#{domain.fetch("id")}:#{axis}" } },
  "verdict"=>domains.all? { |domain| domain.fetch("gaps").empty? } ? "pass" : "incomplete"
}
File.write(File.join(root, "evidence/fe-parity-audit-report.json"), JSON.pretty_generate(report) + "\n")
abort "FE Parityの構造検証に失敗しました" unless domains.all? { |domain| domain.fetch("evidence_errors").empty? && domain.fetch("missing_artifact_signals").empty? }
puts "FE parity audit: domains=#{domains.length} gap_domains=#{report.fetch("gap_domains")} gap_axes=#{report.fetch("gap_axes").length} verdict=#{report.fetch("verdict")}"
