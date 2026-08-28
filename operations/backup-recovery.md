# BackupとRecovery

- Backup成功ログだけを復旧可能性の証拠にしない。
- 対象Version、Encoding、Locale、Extension、Role、Large Object、権限を記録する。
- 本番とは別の隔離Clusterへ復元し、Schema、行数、順序付き論理Digest、Constraintを検証する。
- Restore Drill後に一時ClusterとCredentialを削除する。
- PITRはWAL Archive、Timeline、Recovery Target、停止条件を別のEvidenceとして扱う。
