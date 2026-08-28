#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
required=(
  LICENSE
  NOTICE
  SECURITY.md
  CONTRIBUTING.md
  atlas.yaml
  mastery.yaml
  sources.lock.yaml
  coverage.yaml
  skill.package.yaml
  third_party/manifest.yaml
  sbom.spdx.json
  go.mod
  surface/sql-commands.yaml
)

for path in "${required[@]}"; do
  [[ -s "$ROOT/$path" ]] || { echo "必須Fileがありません: $path" >&2; exit 1; }
done

if rg -n --hidden --glob '!evidence/**' --glob '!.git/**' \
  '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|AKIA[0-9A-Z]{16}|postgres(ql)?://[^[:space:]]+:[^[:space:]@]+@)' "$ROOT"; then
  echo "秘密情報候補を検出しました" >&2
  exit 1
fi

if ! rg -q 'Apache License' "$ROOT/LICENSE"; then
  echo "LICENSEがApache-2.0本文ではありません" >&2
  exit 1
fi

if ! jq -e '.spdxVersion == "SPDX-2.3" and .packages[0].licenseDeclared == "Apache-2.0"' \
  "$ROOT/sbom.spdx.json" >/dev/null; then
  echo "SPDX SBOMが期待形式ではありません" >&2
  exit 1
fi

mkdir -p "$ROOT/evidence/artifacts"
lock_digest="$(sha256_file "$ROOT/sources.lock.yaml")"
coverage_digest="$(awk '/^authority_lock_digest:/ {sub(/^sha256:/, "", $2); print $2}' "$ROOT/coverage.yaml")"
if [[ "$lock_digest" != "$coverage_digest" ]]; then
  echo "Authority Lock DigestがCoverageと一致しません" >&2
  exit 1
fi
jq -n --arg digest "sha256:$lock_digest" \
  '{authority_lock_digest:$digest,coverage_binding:"pass",version_lock:"PostgreSQL 18.6 / REL_18_6",verdict:"pass"}' \
  > "$ROOT/evidence/artifacts/foundation-authority-lock.json"
record_evidence foundation-authority-lock "foundation.authority-lock, foundation.version-lock" test-report local \
  "make test-static" "$ROOT/evidence/artifacts/foundation-authority-lock.json" pass \
  "$ROOT/scripts" foundation.authority-lock

echo '{"rights_files":"pass","secret_scan":"pass","sbom":"pass"}' \
  > "$ROOT/evidence/artifacts/publication-static-gates.json"
record_evidence publication-static-gates publication.provenance test-report local \
  "make test-static" "$ROOT/evidence/artifacts/publication-static-gates.json" pass \
  "$ROOT/scripts" publication.static-gates
ruby "$ROOT/scripts/graph-gates.rb"
echo "公開前の静的Gateを通過しました"
