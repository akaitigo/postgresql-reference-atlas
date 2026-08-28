# Replication診断

まずTopologyと許容Lagの定義を確認する。`pg_stat_replication`、LSN差、Sender、Receiver、Replay、Wait Event、Replication Slot、WAL保持量を読み取り専用で収集する。証拠が矛盾する、Topologyが不明、権限が不足する場合は操作を停止する。Promotion、Slot削除、Standby再構築は明示承認とRollback計画なしに実施しない。
