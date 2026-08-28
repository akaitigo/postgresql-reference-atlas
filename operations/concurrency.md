# MVCC・Lock・Deadlock診断

## 読み取り専用の観測

1. `pg_stat_activity`で`pid`、`xact_start`、`wait_event_type`、`wait_event`、`backend_xid`、`backend_xmin`を採取する。
2. `pg_blocking_pids(pid)`から待機辺を作り、`pg_locks`の`locktype`、`mode`、`granted`、対象Relationを結ぶ。
3. `transaction_isolation`、Transaction開始時刻、直前のSQLSTATE、ApplicationのRetry有無を記録する。
4. 長時間Transaction、Idle in transaction、DDL Lock、Row Lock、Serializable競合を分離する。

## 判断と停止条件

- `55P03`はNOWAITによる即時拒否、`40P01`はDeadlock victim、`40001`はSerializable/Repeatable Readの再試行対象として区別する。
- Backend終了は未確定作業をRollbackする。所有者、影響、Retry安全性を確認するまで`pg_terminate_backend`を実行しない。
- Blocking Sessionを機械的に終了せず、Root blocker、保持中の不変条件、Commit/Rollbackの所有者を先に確定する。

Labは`mvcc`、`locking`、`deadlock`を使い、Snapshot維持、NOWAIT、Deadlock victimをそれぞれ独立して検証する。
