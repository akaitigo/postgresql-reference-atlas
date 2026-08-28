#!/usr/bin/env bash
set -euo pipefail

query="$(printf '%s' "${*:-}" | tr '[:upper:]' '[:lower:]')"
capability="coverage-gap"
mode="review"

case "$query" in
  *postgis*|*pgvector*|*timescaledb*|*rds*|*aurora*) capability="coverage-gap" ;;
  *upgrade*|*アップグレード*|*移行*) capability="lifecycle.upgrade"; mode="migrate" ;;
  *replication*|*replica*|*レプリケーション*|*lag*) capability="operations.replication"; mode="diagnose" ;;
  *backup*|*restore*|*pitr*|*バックアップ*|*復旧*) capability="operations.backup-recovery"; mode="recover" ;;
  *index*|*インデックス*|*索引*) capability="performance.index"; mode="design" ;;
  *planner*|*explain*|*slow*|*実行計画*|*遅い*) capability="performance.planner"; mode="diagnose" ;;
  *mvcc*|*isolation*|*transaction*|*lock*|*トランザクション*|*ロック*) capability="concurrency.mvcc"; mode="diagnose" ;;
  *sql*|*constraint*|*returning*|*制約*|*型*) capability="query.sql-surface"; mode="implement" ;;
esac

jq -n --arg capability "$capability" --arg mode "$mode" \
  '{capability:$capability,mode:$mode,coverage:(if $capability == "coverage-gap" then "outside" else "partial" end)}'
