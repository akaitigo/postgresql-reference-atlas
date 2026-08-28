# VACUUM・ANALYZE・Freeze運用

1. `pg_stat_user_tables`のLive/Dead tuple、Vacuum/Analyze時刻と回数、`age(relfrozenxid)`を採取する。
2. 長時間TransactionとReplication Slotが`xmin`を保持していないか確認する。
3. Autovacuum設定、Table固有Storage Parameter、変更率、Maintenance I/O余力を記録する。
4. `ANALYZE`後は推定行数、`VACUUM`後はDead tupleとFreeze age、`REINDEX`後はIndex妥当性とQuery結果を検証する。

Wraparound防止を通常の空き領域回収と混同しない。`VACUUM FULL`、`CLUSTER`、`REINDEX`、Table rewriteはLockと追加Diskを見積もり、停止条件とRollback境界なしに実行しない。
