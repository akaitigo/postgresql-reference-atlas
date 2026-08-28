#!/usr/bin/env bash
set -euo pipefail

query="$(printf '%s' "${*:-}" | tr '[:upper:]' '[:lower:]')"
capability="coverage-gap"
mode="review"
outcome="choose"

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

case "$query" in
  *agent*|*delegate*|*委任*) outcome="delegate"; mode="review" ;;
  *upgrade*|*migrate*|*アップグレード*|*移行*|*廃止*) outcome="evolve"; mode="migrate" ;;
  *verify*|*test*|*evidence*|*検証*|*試験*|*証拠*) outcome="verify"; mode="review" ;;
  *monitor*|*operate*|*監視*|*運用*|*容量*) outcome="operate"; mode="diagnose" ;;
  *diagnose*|*slow*|*lag*|*troubleshoot*|*診断*|*遅い*|*障害*|*復旧*) outcome="troubleshoot" ;;
  *implement*|*build*|*create*|*実装*|*構築*|*作成*) outcome="build"; mode="implement" ;;
  *explain*|*understand*|*仕組み*|*原理*|*説明*) outcome="understand"; mode="review" ;;
  *choose*|*design*|*選択*|*選ぶ*|*設計*) outcome="choose"; mode="design" ;;
esac

if [[ "$capability" == "coverage-gap" ]]; then
  mode="review"
fi

jq -n --arg capability "$capability" --arg mode "$mode" --arg outcome "$outcome" \
  '{capability:$capability,mode:$mode,outcome:$outcome,coverage:(if $capability == "coverage-gap" then "outside" else "partial" end)}'
