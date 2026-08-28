# Safety Boundary

- 診断は読み取り専用から開始する。
- 対象Version、接続先、Role、Topologyが不明なら変更を止める。
- Recovery、Replication、Upgradeの自動操作はAtlas Harnessが生成した一時Resourceだけを対象にする。
- 実環境では変更計画、事前条件、検証、Rollback、承認点を提示するまで実行しない。
- `pg_resetwal`、WAL削除、Promotion、Slot削除、Table Rewriteは通常手順に含めない。
