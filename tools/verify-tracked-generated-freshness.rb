#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/tracked_generated_freshness"

count = TrackedGeneratedFreshness.verify!("all-tracked")
puts "Verified tracked generated outputs are fresh: #{count} files"
