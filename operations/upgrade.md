# Major Upgrade計画

Upgrade方式を`pg_upgrade`と論理Dump/Restoreで比較し、停止時間、Disk、Extension、Collation、Replica、Rollback境界を明記する。事前に`pg_upgrade --check`相当、Backup復元、Extension互換性、Application互換性を検証する。Upgrade後は統計、Index、Sequence、権限、論理Digest、性能回帰を確認し、Rollback不能点の前で承認を得る。
