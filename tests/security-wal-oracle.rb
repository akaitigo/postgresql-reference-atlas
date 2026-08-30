#!/usr/bin/env ruby
# frozen_string_literal: true

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))

abort "WAL segment switch predicate constant is missing" unless source.include?('WAL_SEGMENT_SWITCH_PREDICATE = "switched_lsn >= end_lsn"')
abort "WAL segment switch predicate should be reused exactly twice" unless source.scan('#{WAL_SEGMENT_SWITCH_PREDICATE}').length == 2
abort "WAL verdict regressed to live LSN re-read" if source.include?("switched_lsn >= pg_current_wal_insert_lsn()")

puts "WAL security oracle contractを検証しました: predicate reused twice and live-LSN reread rejected"
