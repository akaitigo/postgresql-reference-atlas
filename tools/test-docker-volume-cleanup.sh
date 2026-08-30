#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

suffix="$$-$(date +%s)"
success_container="pgra-volume-cleanup-success-${suffix}"
failure_container="pgra-volume-cleanup-failure-${suffix}"
owned_volumes=""

cleanup_owned() {
  docker rm -f -v "$success_container" "$failure_container" >/dev/null 2>&1 || true
  for volume in $owned_volumes; do
    docker volume rm "$volume" >/dev/null 2>&1 || true
  done
}
trap cleanup_owned EXIT

anonymous_data_volume() {
  docker inspect --format '{{range .Mounts}}{{if and (eq .Type "volume") (eq .Destination "/var/lib/postgresql")}}{{.Name}}{{end}}{{end}}' "$1"
}

assert_removed() {
  if docker volume inspect "$1" >/dev/null 2>&1; then
    die "task-owned anonymous volumeが残っています: $1"
  fi
}

run_cleanup_case() {
  local container="$1"
  local outcome="$2"
  docker run --detach --name "$container" --label org.reference-atlas.owner=postgresql-reference-atlas \
    "$PG18_IMAGE" sh -ceu 'while :; do sleep 3600; done' >/dev/null
  local volume
  volume="$(anonymous_data_volume "$container")"
  [[ -n "$volume" ]] || die "PostgreSQL anonymous data volumeを特定できません"
  owned_volumes="$owned_volumes $volume"

  if [[ "$outcome" == success ]]; then
    (
      trap 'docker rm -f -v "$container" >/dev/null 2>&1 || true' EXIT
      true
    )
  else
    if (
      trap 'docker rm -f -v "$container" >/dev/null 2>&1 || true' EXIT
      false
    ); then
      die "failure pathが成功扱いになりました"
    fi
  fi
  assert_removed "$volume"
}

run_cleanup_case "$success_container" success
run_cleanup_case "$failure_container" failure
echo "Docker volume cleanup contractを検証しました: success/failure trap 2/2、anonymous volume leak 0"
