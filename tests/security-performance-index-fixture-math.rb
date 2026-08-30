#!/usr/bin/env ruby
# frozen_string_literal: true

range = 1..200_000
target_tenant = ->(g) { (g % 1000) == 42 }
independent_billed = ->(g) { ((g / 1000) % 2).zero? }
all_even_billed = ->(g) { g.even? }

target_rows = range.count { |g| target_tenant.call(g) }
target_billed_rows = range.count { |g| target_tenant.call(g) && independent_billed.call(g) }
target_all_even_rows = range.count { |g| target_tenant.call(g) && all_even_billed.call(g) }
target_shrunk_rows = (1..100_000).count { |g| target_tenant.call(g) }

abort "tenant row denominator drifted" unless target_rows == 200
abort "billed visible row denominator drifted" unless target_billed_rows == 100
abort "all-even tenant regression no longer reproduces 200 billed rows" unless target_all_even_rows == 200
abort "tenant shrink negative no longer reproduces 100 tenant rows under half-range" unless target_shrunk_rows == 100

puts "performance.index fixture mathを検証しました: tenant_rows=200 billed_visible_rows=100 all-even regression=200 and half-range shrink=100"
