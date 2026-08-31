#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require_relative "lib/scenario_closure_plan"

plan = ScenarioClosurePlan.build
output = ScenarioClosurePlan.absolute(ScenarioClosurePlan::PLAN_PATH)
FileUtils.mkdir_p(File.dirname(output))
File.write(output, JSON.pretty_generate(plan) + "\n")
puts "Generated PostgreSQL Scenario Closure Plan: #{plan.dig('summary', 'remaining_rows')} rows / #{plan.dig('summary', 'planned_tranches')} tranches; next=#{plan.dig('next_tranche', 'id') || 'none'}"
