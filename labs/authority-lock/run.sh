#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/lib.sh"
require_command docker
require_command jq
require_command ruby

artifact="$ROOT/evidence/artifacts/authority-lock.json"
lock_digest="$(sha256_file "$ROOT/sources.lock.yaml")"
coverage_digest="$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("authority_lock_digest").delete_prefix("sha256:")' "$ROOT/coverage.yaml")"
[[ "$lock_digest" == "$coverage_digest" ]] || die "Authority Lock DigestがCoverageと一致しません"

runtime_versions='[]'
for spec in \
  'postgres:18.6-alpine@sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2|18.6' \
  'postgres:17.11-alpine@sha256:18cfe3ef5e6815560c98237d6216d1e5119702fb0f3894c8785dd58b8bbe5d73|17.11' \
  'postgres:16.15-alpine3.23@sha256:421b84e07a72bb8f3715f20501a1fdbe1219aad1fa4af7786a49d9a3f2480296|16.15' \
  'postgres:15.19-alpine3.23@sha256:b0dc4a8dc256b963ee25867843d9fd366850e327e4a2a65ccb3c47262d092973|15.19' \
  'postgres:14.24-alpine@sha256:727876d274666da0b92a445390ba093c84b8e9f8343e1c53cd4e9a7ab2d85310|14.24'; do
  image="${spec%%|*}"
  expected="${spec##*|}"
  observed="$(docker run --rm "$image" postgres --version)"
  [[ "$observed" == *" $expected" ]] || die "Runtime Version不一致: $image / $observed"
  image_id="$(docker_image_id "$image")"
  runtime_versions="$(jq -c --arg image "$image" --arg version "$expected" --arg observed "$observed" --arg image_id "$image_id" '. + [{image:$image,expected:$version,observed:$observed,image_id:$image_id,result:"pass"}]' <<<"$runtime_versions")"
done

jq -n --arg digest "sha256:$lock_digest" --argjson runtimes "$runtime_versions" \
  '{authority_lock_digest:$digest,documentation_version:"18.6",release_version:"18.6",source_tag:"REL_18_6",source_commit:"724edf9bde9d356724ad384a2e196edc3c9f80f7",runtime_versions:$runtimes,unexplained_differences:0,verdict:"pass"}' > "$artifact"
record_evidence authority-lock foundation.authority-lock conformance local "make lab LAB=authority-lock" "$artifact" pass
echo "Authority Lockの複数Source照合を通過しました"
