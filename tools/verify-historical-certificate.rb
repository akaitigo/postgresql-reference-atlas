#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

root = File.expand_path("..", __dir__)
migration = YAML.safe_load(File.read(File.join(root, "migrations/non-regression-v2.yaml")), aliases: false)
mapping = migration.fetch("replacements").find { |item| item.fetch("id") == "completion-certificate-history-copy" }
abort "Certificate Mappingがありません" unless mapping
path = File.join(root, mapping.fetch("new_id").delete_prefix("file:"))
actual_digest = "sha256:#{Digest::SHA256.file(path).hexdigest}"
abort "Historical Certificateのbyte digestがBaselineと一致しません" unless actual_digest == mapping.fetch("old_value") && actual_digest == mapping.fetch("new_value")
certificate = JSON.parse(File.read(path))
signature = certificate.fetch("signature")
payload = certificate.reject { |key, _value| key == "signature" }
payload_digest = "sha256:#{Digest::SHA256.hexdigest(JSON.generate(payload))}"
abort "Historical Certificateのpayload signatureが一致しません" unless signature.fetch("type") == "payload-sha256" && signature.fetch("digest") == payload_digest
abort "Historical Certificateの証明対象commitが変わっています" unless certificate.fetch("commit") == "9704d11b19a65755cb6d5738131d104d48309ef5"
puts "Bounded historical Certificateを検証しました: digest=#{actual_digest} source_commit=#{certificate.fetch("commit")}"
