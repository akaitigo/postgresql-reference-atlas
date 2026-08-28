#!/usr/bin/env bash
set -euo pipefail

query="$(printf '%s' "${*:-}" | tr '[:upper:]' '[:lower:]')"
capability="coverage-gap"
mode="review"
outcome="choose"
coverage="outside"
lab=""
runbook=""
safety="stop"

case "$query" in
  *postgis*|*pgvector*|*timescaledb*|*rds*|*aurora*|*cloud\ sql*) ;;
  *compatibility\ matrix*|*互換性マトリクス*) capability="lifecycle.compatibility-matrix"; mode="review"; coverage="covered"; lab="labs/compatibility-matrix"; runbook="operations/upgrade.md"; safety="isolated-lab" ;;
  *pg_upgrade*|*pg-upgrade*|*binary\ upgrade*|*バイナリアップグレード*) capability="lifecycle.pg-upgrade"; mode="migrate"; coverage="covered"; lab="labs/pg-upgrade"; runbook="operations/upgrade.md"; safety="requires-approval" ;;
  *not\ valid*|*validate\ constraint*|*concurrently*|*schema\ migration*|*スキーマ移行*) capability="lifecycle.schema-migration"; mode="migrate"; coverage="covered"; lab="labs/migration"; runbook="operations/migration.md"; safety="requires-approval" ;;
  *upgrade*|*アップグレード*|*メジャー移行*) capability="lifecycle.upgrade"; mode="migrate"; coverage="covered"; lab="labs/upgrade"; runbook="operations/upgrade.md"; safety="requires-approval" ;;
  *logical\ replication*|*論理レプリケーション*|*publication*|*subscription*) capability="operations.logical-replication"; mode="diagnose"; coverage="covered"; lab="labs/logical-replication"; runbook="operations/replication.md"; safety="requires-approval" ;;
  *physical\ replication*|*streaming\ replication*|*standby*|*物理レプリケーション*) capability="operations.replication"; mode="diagnose"; coverage="covered"; lab="labs/replication"; runbook="operations/replication.md"; safety="requires-approval" ;;
  *pitr*|*point-in-time*|*ポイントインタイム*) capability="operations.pitr-recovery"; mode="recover"; coverage="covered"; lab="labs/pitr"; runbook="operations/backup-recovery.md"; safety="requires-approval" ;;
  *backup*|*restore*|*バックアップ*|*復元*|*復旧*) capability="operations.backup-recovery"; mode="recover"; coverage="partial"; lab="labs/backup-recovery"; runbook="operations/backup-recovery.md"; safety="requires-approval" ;;
  *failure\ injection*|*backend\ kill*|*障害注入*|*強制終了*) capability="operations.failure-injection"; mode="recover"; coverage="covered"; lab="labs/failure-injection"; runbook="operations/failure-response.md"; safety="isolated-lab" ;;
  *vacuum*|*autovacuum*|*analyze*|*freeze*|*メンテナンス*) capability="operations.maintenance"; mode="diagnose"; coverage="covered"; lab="labs/maintenance"; runbook="operations/maintenance.md"; safety="read-only-first" ;;
  *observability*|*pg_stat*|*monitor*|*監視*|*可観測性*) capability="operations.observability"; mode="diagnose"; coverage="covered"; lab="labs/observability"; runbook="operations/observability.md"; safety="read-only-first" ;;
  *wal*|*write-ahead*) capability="operations.wal"; mode="review"; coverage="covered"; lab="labs/wal"; runbook="operations/backup-recovery.md"; safety="read-only-first" ;;
  *rls*|*row\ level\ security*|*scram*|*security\ definer*|*権限*|*セキュリティ*) capability="query.security"; mode="design"; coverage="covered"; lab="labs/security"; runbook="operations/security.md"; safety="requires-approval" ;;
  *catalog*|*カタログ*) capability="query.catalog-inventory"; mode="review"; coverage="covered"; lab="labs/catalog-inventory"; safety="read-only-first" ;;
  *partition*|*パーティション*) capability="query.partitioning"; mode="design"; coverage="covered"; lab="labs/partitioning"; safety="isolated-lab" ;;
  *extension*|*pg_trgm*|*拡張*) capability="query.extension"; mode="implement"; coverage="covered"; lab="labs/extension"; safety="isolated-lab" ;;
  *type*|*domain*|*enum*|*range*|*uuidv7*|*型*) capability="query.types-constraints"; mode="implement"; coverage="covered"; lab="labs/types-constraints"; safety="isolated-lab" ;;
  *deadlock*|*デッドロック*) capability="concurrency.deadlock"; mode="diagnose"; coverage="covered"; lab="labs/deadlock"; runbook="operations/concurrency.md"; safety="read-only-first" ;;
  *nowait*|*row\ lock*|*ロック待ち*) capability="concurrency.locking"; mode="diagnose"; coverage="covered"; lab="labs/locking"; runbook="operations/concurrency.md"; safety="read-only-first" ;;
  *mvcc*|*isolation*|*transaction*|*トランザクション*|*分離レベル*) capability="concurrency.mvcc"; mode="diagnose"; coverage="covered"; lab="labs/mvcc"; runbook="operations/concurrency.md"; safety="read-only-first" ;;
  *extended\ statistics*|*拡張統計*|*statistics*) capability="performance.statistics"; mode="diagnose"; coverage="covered"; lab="labs/statistics"; runbook="operations/diagnose-query.md"; safety="read-only-first" ;;
  *index*|*インデックス*|*索引*) capability="performance.index"; mode="design"; coverage="covered"; lab="labs/index"; runbook="operations/diagnose-query.md"; safety="isolated-lab" ;;
  *planner*|*explain*|*slow*|*実行計画*|*遅い*) capability="performance.planner"; mode="diagnose"; coverage="covered"; lab="labs/planner"; runbook="operations/diagnose-query.md"; safety="read-only-first" ;;
  *performance*|*buffer*|*capacity*|*性能*|*容量*) capability="performance.execution"; mode="diagnose"; coverage="covered"; lab="labs/performance"; runbook="operations/diagnose-query.md"; safety="read-only-first" ;;
  *sql*|*constraint*|*returning*|*制約*) capability="query.sql-surface"; mode="implement"; coverage="partial"; lab="labs/sql"; safety="isolated-lab" ;;
esac

case "$query" in
  *agent*|*delegate*|*委任*) outcome="delegate"; mode="review" ;;
  *upgrade*|*migrate*|*migration*|*アップグレード*|*移行*|*廃止*) outcome="evolve"; mode="migrate" ;;
  *verify*|*test*|*evidence*|*検証*|*試験*|*証拠*) outcome="verify"; mode="review" ;;
  *monitor*|*operate*|*監視*|*運用*|*容量*) outcome="operate"; mode="diagnose" ;;
  *diagnose*|*slow*|*lag*|*troubleshoot*|*診断*|*遅い*|*障害*|*復旧*) outcome="troubleshoot" ;;
  *implement*|*build*|*create*|*実装*|*構築*|*作成*) outcome="build"; mode="implement" ;;
  *explain*|*understand*|*仕組み*|*原理*|*説明*) outcome="understand"; mode="review" ;;
  *choose*|*design*|*選択*|*選ぶ*|*設計*) outcome="choose"; mode="design" ;;
esac

if [[ "$capability" == "coverage-gap" ]]; then
  mode="review"
  safety="stop"
fi
evidence=""
[[ -n "$lab" ]] && evidence="evidence/$(basename "$lab").evidence.yaml"

jq -n --arg capability "$capability" --arg mode "$mode" --arg outcome "$outcome" \
  --arg coverage "$coverage" --arg version "18.6" --arg lab "$lab" --arg runbook "$runbook" \
  --arg evidence "$evidence" --arg safety "$safety" \
  '{capability:$capability,mode:$mode,outcome:$outcome,coverage:$coverage,version:$version,safety:$safety,lab:(if $lab == "" then null else $lab end),runbook:(if $runbook == "" then null else $runbook end),evidence:(if $evidence == "" then null else $evidence end)}'
