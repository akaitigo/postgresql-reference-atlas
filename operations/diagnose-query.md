# Query診断

1. PostgreSQL Version、Query全文、Parameter、期待Latency、実データ量を確認する。
2. `EXPLAIN (ANALYZE, BUFFERS, WAL, SETTINGS, FORMAT JSON)`は副作用のないQueryに限定する。変更QueryはRollback可能な隔離環境で扱う。
3. 推定行数差、Scan、Join、Sort spill、Lock wait、I/O waitを分けて観測する。
4. Index追加やGUC変更を先に提案せず、原因仮説と反証条件を提示する。
5. 変更前後で結果集合、不変条件、書込み費用、Plan構造を再検証する。
