# 統合Reference System Lab

固定したPostgreSQL 18.6 Container内で、Tenant RLS、Range Partition、Index実行Plan、`NOWAIT`拒否とLock解放後の回復、WAL増分、`pg_stat_statements`を同一Order Systemへ接続して検証する。

このLabが閉じるのは上記の統合Sliceだけである。Backup/PITR、Replication、Upgrade、全Authority Behaviorの統合は別途未Closureとして残す。
