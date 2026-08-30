#!/usr/bin/env bash
set -euo pipefail

ATLAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG18_IMAGE="${PG18_IMAGE:-postgres:18.6-alpine@sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2}"
PG17_IMAGE="${PG17_IMAGE:-postgres:17.11-alpine@sha256:18cfe3ef5e6815560c98237d6216d1e5119702fb0f3894c8785dd58b8bbe5d73}"

die() {
  echo "エラー: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "必要なCommandがありません: $1"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

directory_digest() {
  local directory="$1"
  (
    cd "$directory"
    find . -type f -print0 \
      | sort -z \
      | xargs -0 shasum -a 256 \
      | shasum -a 256 \
      | awk '{print $1}'
  )
}

write_harness_manifest() {
  local name="$1"
  shift
  local manifest="$ATLAS_ROOT/evidence/harnesses/${name}.manifest"
  local paths_file
  paths_file="$(mktemp)"
  mkdir -p "$ATLAS_ROOT/evidence/harnesses"

  local directory file relative
  for directory in "$@" "$ATLAS_ROOT/scripts"; do
    [[ -d "$directory" ]] || die "Harness Directoryがありません: $directory"
    while IFS= read -r -d '' file; do
      relative="${file#"$ATLAS_ROOT/"}"
      [[ "$relative" != evidence/harnesses/* ]] && printf '%s\n' "$relative" >> "$paths_file"
    done < <(find "$directory" -type f -print0)
  done

  : > "$manifest"
  while IFS= read -r relative; do
    printf '%s  %s\n' "$(sha256_file "$ATLAS_ROOT/$relative")" "$relative" >> "$manifest"
  done < <(LC_ALL=C sort -u "$paths_file")
  rm -f "$paths_file"
  printf '%s\n' "$manifest"
}

wait_postgres() {
  local container="$1"
  local attempts=60
  local consecutive=0
  while [[ "$consecutive" -lt 2 ]]; do
    if docker exec "$container" psql -X -qAt -U postgres -d postgres -c 'SELECT 1' 2>/dev/null | grep -qx 1; then
      consecutive=$((consecutive + 1))
    else
      consecutive=0
    fi
    attempts=$((attempts - 1))
    if [[ "$attempts" -eq 0 ]]; then
      docker logs "$container" >&2 || true
      die "PostgreSQLが起動しませんでした: $container"
    fi
    sleep 1
  done
}

wait_postgres_database() {
  local container="$1"
  local database="$2"
  local attempts=60
  until docker exec "$container" psql -X -qAt -U postgres -d "$database" -c 'SELECT 1' 2>/dev/null | grep -qx 1; do
    attempts=$((attempts - 1))
    if [[ "$attempts" -eq 0 ]]; then
      docker logs "$container" >&2 || true
      die "PostgreSQL Databaseが利用可能になりませんでした: $container/$database"
    fi
    sleep 1
  done
}

record_evidence() {
  local lab="$1"
  local claim="$2"
  local kind="$3"
  local profile="$4"
  local command="$5"
  local artifact="$6"
  local verdict="$7"
  local harness_directory="${8:-$ATLAS_ROOT/labs/$lab}"
  local evidence_id="${9:-lab.$lab}"
  local additional_harness_directory="${10:-}"
  local source_digest harness_digest harness_path environment_digest artifact_digest artifact_size created_at evidence_path

  source_digest="$(sha256_file "$ATLAS_ROOT/sources.lock.yaml")"
  if [[ -n "$additional_harness_directory" ]]; then
    harness_path="$(write_harness_manifest "$lab" "$harness_directory" "$additional_harness_directory")"
  else
    harness_path="$(write_harness_manifest "$lab" "$harness_directory")"
  fi
  harness_digest="$(sha256_file "$harness_path")"
  environment_digest="$(sha256_file "$ATLAS_ROOT/environments/$profile.yaml")"
  artifact_digest="$(sha256_file "$artifact")"
  artifact_size="$(wc -c < "$artifact" | tr -d ' ')"
  created_at="${EVIDENCE_CREATED_AT:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
  evidence_path="$ATLAS_ROOT/evidence/${lab}.evidence.yaml"

  mkdir -p "$ATLAS_ROOT/evidence/artifacts"
  if [[ "$artifact" != "$ATLAS_ROOT/evidence/artifacts/${lab}.json" ]]; then
    cp "$artifact" "$ATLAS_ROOT/evidence/artifacts/${lab}.json"
  fi

  cat > "$evidence_path" <<EOF
schema_version: 1
id: ${evidence_id}
atlas_id: postgresql-reference-atlas
claim_ids: [${claim}]
kind: ${kind}
producer: postgresql-reference-atlas
command: ${command}
created_at: "${created_at}"
environment:
  profile: ${profile}
  manifest_digest: sha256:${environment_digest}
source_digest: sha256:${source_digest}
harness_digest: sha256:${harness_digest}
harness_path: ${harness_path#"$ATLAS_ROOT/"}
artifact:
  uri: evidence/artifacts/${lab}.json
  digest: sha256:${artifact_digest}
  media_type: application/json
  size_bytes: ${artifact_size}
verdict: ${verdict}
retention: git
EOF
}

docker_image_id() {
  docker image inspect "$1" --format '{{.Id}}'
}
