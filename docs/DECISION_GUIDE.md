# PostgreSQL 18.6 判断ガイド

この表は最終回答ではなく、条件を対応Capability、Lab、Evidenceへ落とす入口である。

| 判断 | 第一候補 | 切替条件 | 必須検証 |
|---|---|---|---|
| ConstraintかApplication検証か | Database Constraint | 外部Systemを跨ぐ不変条件はApplication/Workflowも併用 | SQLSTATE、既存データ検証、Migration Lock |
| B-treeかGIN/GiST/BRINか | B-tree | 包含/類似、範囲、物理相関でOperator Classを選ぶ | 結果不変性、JSON Plan、Size、Write WAL |
| Read CommittedかRepeatable Read/Serializableか | Read Committed | Transaction内Snapshot不変性、Write skew防止要件で強化 | 競合Schedule、40001/40P01 Retry、Lock wait |
| Partitionか単一Tableか | 単一Table | Lifecycle分離、pruning、保守単位が明確な場合にPartition | Routing、Pruning、Unique/FK境界、Partition数Cost |
| 論理BackupかPhysical Backupか | RPO/RTOから選択 | Object選択/可搬性は論理、PITR/大容量はPhysical | 隔離Restore、Digest、WAL archive、復旧停止点 |
| PhysicalかLogical Replicationか | Physical | Table選択、異Version、変換要件ならLogical | Lag/Slot/WAL保持、DDL責任、Failover手順 |
| Dump/Restoreかpg_upgradeか | 停止時間と互換性で選択 | 短時間・同一Platformはpg_upgrade、再編成/選択移行は論理 | Extension、Collation、Disk、check、Digest、Rollback不能点 |
| 手動MaintenanceかAutovacuum調整か | Autovacuum | 緊急Freeze、個別Table特性、Bulk変動時に明示実行 | xmin保持者、Dead tuple、Freeze age、I/O/Lock |

外部Extension、Managed Service、HA/Pooler固有判断はCoverage外。類似する本体機能のEvidenceを代用しない。
