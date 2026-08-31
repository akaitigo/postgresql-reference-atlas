#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../../../../tools/lib/postgresql-skill-routing"

root = File.expand_path("../../../../", __dir__)
request = JSON.parse(ARGV[0] || STDIN.read)
puts JSON.pretty_generate(PostgreSQLSkillRouting.plan(root, request))
