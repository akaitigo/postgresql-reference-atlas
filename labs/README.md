# Lab Index

全Labは`make lab LAB=<id>`で起動し、固定Image、隔離Container/Network/Volume、明示Cleanupを使う。成功条件は表示文字列ではなくSQLSTATE、論理Digest、JSON Plan、LSN、Catalog/System View、行集合Oracleで判定し、`evidence/`へSource/Harness/Environment Digest付きRecordを生成する。

| Surface | Lab | 主要Oracle |
|---|---|---|
| SQL | `sql` | RETURNING、23505、23514 |
| 型/Constraint | `types-constraints` | Round-trip、UUIDv7、Domain拒否 |
| Runtime Inventory | `catalog-inventory` | 型・関数・演算子・Cast・AM・Collation・Extension・Catalogの件数/Digest |
| Partition | `partitioning` | Routing、Plan pruning |
| Extension | `extension` | pg_trgm、GIN Plan |
| Security | `security` | RLS 42501、SCRAM verifier、HBA、search_path |
| MVCC/Lock | `mvcc` / `locking` / `deadlock` | Snapshot、55P03、40P01 |
| Planner/Statistics/Index | `planner` / `statistics` / `index` | JSON Plan、推定行数、結果Digest |
| Performance | `performance` | ANALYZE、BUFFERS、WAL、Relation Size |
| WAL/Backup/Recovery | `wal` / `backup-recovery` / `pitr` | LSN、Restore Digest、名前付き復旧点 |
| Replication | `replication` / `logical-replication` | Replay、Recovery状態、Slot、Apply Worker |
| Operations | `observability` / `maintenance` / `failure-injection` | pg_stat、Dead tuple、Rollback後Service継続 |
| Migration/Upgrade | `migration` / `upgrade` / `pg-upgrade` | VALIDATE、Version境界、論理Digest、pg_upgrade check |
| Compatibility（実行保留） | `compatibility-matrix` | 14.24〜18.6の同一Fixture、Digest、Feature transition |

実環境操作へ転用しない。Promotion、Backend終了、Slot削除、PITR、Upgradeは対応Runbookの承認点と停止条件を先に適用する。
