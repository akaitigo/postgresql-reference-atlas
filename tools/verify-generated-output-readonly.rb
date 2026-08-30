#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/tracked_generated_freshness"

name = ARGV.fetch(0)
count = TrackedGeneratedFreshness.verify!(name)
puts "Verified read-only generated output freshness (#{name}): #{count} files"
