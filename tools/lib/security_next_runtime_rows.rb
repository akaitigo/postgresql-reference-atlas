# frozen_string_literal: true

require_relative "security_scenario_tranche"

module SecurityNextRuntimeRows
  module_function

  def completed_rows(plan = SecurityScenarioTranche.load_plan)
    SecurityScenarioTranche.verify_completed_suite!(plan).map do |row|
      {
        "id"=>SecurityScenarioTranche.row_id_for(row.fetch("pattern_id"), row.fetch("scenario")),
        "pattern_id"=>row.fetch("pattern_id"),
        "target_id"=>row.fetch("pattern_id").sub("definitive-domain.", ""),
        "scenario"=>row.fetch("scenario"),
        "risk_rank"=>1
      }
    end
  end

  def next_runtime_tranche(plan = SecurityScenarioTranche.load_plan)
    SecurityScenarioTranche.verify_next_runtime_tranche!(plan)
  end

  def next_runtime_rows(plan = SecurityScenarioTranche.load_plan)
    verify_selected_rows!(completed_rows(plan) + following_rows(plan), plan: plan)
  end

  def following_rows(plan = SecurityScenarioTranche.load_plan)
    rows_by_id = plan.fetch("rows").each_with_object({}) do |row, memo|
      memo[row.fetch("id")] = normalize_row(row)
    end
    SecurityScenarioTranche.expected_following_row_ids.map do |row_id|
      rows_by_id.fetch(row_id) { raise "security next runtime row missing from closure plan: #{row_id}" }
    end
  end

  def unsupported_scenarios(rows, supported: ["security"])
    rows.map { |row| row.fetch("scenario") }.uniq - supported
  end

  def verify_security_command_supported!(rows = next_runtime_rows)
    unsupported = unsupported_scenarios(rows)
    return true if unsupported.empty?

    raise "security runtime command only supports security rows; next runtime includes unsupported scenarios: #{unsupported.join(', ')}"
  end

  def verify_selected_rows!(rows, plan: SecurityScenarioTranche.load_plan)
    completed = completed_rows(plan)
    expected_row_ids = completed.map { |row| row.fetch("id") } + SecurityScenarioTranche.expected_following_row_ids
    actual_row_ids = rows.map { |row| row.fetch("id") }
    raise "security next runtime row_ids drifted" unless actual_row_ids == expected_row_ids
    raise "security next runtime cardinality drifted" unless rows.length == expected_row_ids.length
    raise "security next runtime row identity drifted" unless rows.map { |row| [row.fetch("id"), row.fetch("pattern_id"), row.fetch("scenario")] }.uniq.length == rows.length
    raise "security next runtime must preserve duplicate pattern_ids across scenarios" unless rows.map { |row| row.fetch("pattern_id") }.uniq.length == completed.length
    raise "security next runtime trailing refusal rows drifted" unless rows.last(SecurityScenarioTranche.expected_following_row_ids.length).all? { |row| row.fetch("scenario") == "refusal" }
    rows
  end

  def normalize_row(row)
    row.slice("id", "pattern_id", "target_id", "scenario", "risk_rank")
  end
end
