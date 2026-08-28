# 障害注入と回復確認

障害注入は`pgra-*`の一時Resourceだけで行う。注入前に正常時Oracle、注入点、期待SQLSTATE/状態、最大待機時間、Cleanupを固定する。

- Backend終了: 未確定変更のRollbackと新規接続・確定Writeを確認する。
- Deadlock: Victimが1 Transactionだけで、残存Transactionの不変条件が保たれることを確認する。
- Primary停止: Client timeout、Standby追随位置、Promotion権限、Split-brain防止を別々に扱う。
- WAL/Storage破壊: 通常Drillでは実施せず、Base BackupとArchive WALを使う隔離Recoveryを優先する。

本番Resourceへの`pg_terminate_backend`、Promotion、Slot削除、WAL削除、`pg_resetwal`はこのRunbookの自動実行範囲外である。
