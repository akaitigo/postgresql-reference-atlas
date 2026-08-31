#!/usr/bin/env ruby
# frozen_string_literal: true

source = File.read(File.expand_path("../tools/run-scenario-security-001.rb", __dir__))

abort "security runtime environment must stay single-worker" unless source.include?('"workers"=>1')
abort "security runtime retries must stay zero" unless source.include?('"retries"=>0')
abort "security runtime records must stay first-attempt only" unless source.include?('"attempts"=>1')
abort "security runtime records must stay passed-only at publish time" unless source.include?('"final_status"=>"passed"')
abort "security runtime publisher must still enforce passed full-run publication" unless source.include?('publisher.publish(run_status: "passed")')

puts "Security runtime contractを検証しました: workers=1 retries=0 first-attempt publish-only"
