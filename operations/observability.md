# Observability

## 最小観測面

- Session: `pg_stat_activity`、`pg_blocking_pids()`、`pg_locks`
- Query: `pg_stat_statements`（`shared_preload_libraries`と`compute_query_id`を事前確認）
- Database/Table/Index: `pg_stat_database`、`pg_stat_user_tables`、`pg_stat_user_indexes`
- WAL/Checkpoint: `pg_stat_wal`、`pg_stat_checkpointer`、`pg_stat_archiver`
- Replication: `pg_stat_replication`、`pg_stat_subscription`、`pg_replication_slots`
- Capacity: `pg_database_size`、`pg_total_relation_size`、WAL/Slot保持量

統計は累積値であり、Reset時刻、取得窓、負荷量と一緒に保存する。単一Snapshotを因果関係とみなさず、Query ID、Plan、Wait、I/O、Lock、WALを同じ時間窓で関連付ける。設定変更やResetは観測を破壊するため、明示承認なしに行わない。
