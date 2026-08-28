# Capability Index

正式対象はPostgreSQL 18.6。`coverage.yaml`の状態を正本とし、Routerは次の入口へ案内する。

| 問い | Capability | Lab | Runbook |
|---|---|---|---|
| SQL、Constraint、RETURNING | `query.sql-surface` | `labs/sql` | — |
| 型、Domain、Range、UUIDv7 | `query.types-constraints` | `labs/types-constraints` | — |
| Runtime Catalog Inventory | `query.catalog-inventory` | `labs/catalog-inventory` | — |
| Partitioning | `query.partitioning` | `labs/partitioning` | — |
| 公式同梱Extension | `query.extension` | `labs/extension` | — |
| Role、RLS、SCRAM | `query.security` | `labs/security` | `operations/security.md` |
| MVCC、Isolation | `concurrency.mvcc` | `labs/mvcc` | `operations/concurrency.md` |
| Row Lock、NOWAIT | `concurrency.locking` | `labs/locking` | `operations/concurrency.md` |
| Deadlock | `concurrency.deadlock` | `labs/deadlock` | `operations/concurrency.md` |
| Planner | `performance.planner` | `labs/planner` | `operations/diagnose-query.md` |
| Extended Statistics | `performance.statistics` | `labs/statistics` | `operations/diagnose-query.md` |
| Index | `performance.index` | `labs/index` | `operations/diagnose-query.md` |
| 実行時Plan、Buffer、容量 | `performance.execution` | `labs/performance` | `operations/diagnose-query.md` |
| WAL | `operations.wal` | `labs/wal` | `operations/backup-recovery.md` |
| Dump/Restore | `operations.backup-recovery` | `labs/backup-recovery` | `operations/backup-recovery.md` |
| PITR | `operations.pitr-recovery` | `labs/pitr` | `operations/backup-recovery.md` |
| Physical Replication | `operations.replication` | `labs/replication` | `operations/replication.md` |
| Logical Replication | `operations.logical-replication` | `labs/logical-replication` | `operations/replication.md` |
| Observability | `operations.observability` | `labs/observability` | `operations/observability.md` |
| VACUUM、ANALYZE、Freeze | `operations.maintenance` | `labs/maintenance` | `operations/maintenance.md` |
| Failure Injection | `operations.failure-injection` | `labs/failure-injection` | `operations/failure-response.md` |
| Online Schema Migration | `lifecycle.schema-migration` | `labs/migration` | `operations/migration.md` |
| Logical Major Upgrade | `lifecycle.upgrade` | `labs/upgrade` | `operations/upgrade.md` |
| Binary Major Upgrade | `lifecycle.pg-upgrade` | `labs/pg-upgrade` | `operations/upgrade.md` |
| 14.24-18.6互換性（planned） | `lifecycle.compatibility-matrix` | `labs/compatibility-matrix` | `operations/upgrade.md` |

外部Extension、Managed Service、外部HA/Poolerは`coverage-gap`。Evidenceのない対象を類似Capabilityで代用しない。
