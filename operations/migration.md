# Online Schema Migration

## Expand–Migrate–Contract

1. Expand: Nullable Column、`NOT VALID` Constraint、互換Indexなど旧新Applicationが共存できる構造を追加する。
2. Migrate: Chunk単位でBackfillし、Lock時間、WAL量、Replica Lag、Error率を観測する。
3. Validate: `VALIDATE CONSTRAINT`、結果Digest、Query Plan、権限、Application互換性を検証する。
4. Contract: 旧Column/Constraint/Indexの利用がゼロであることを確認し、別Releaseで削除する。

`CREATE INDEX CONCURRENTLY`は失敗時に無効Indexを残し得る。`pg_index.indisvalid`を確認し、再試行前に対象を識別する。型変更やDefault追加がTable rewriteを起こすか18.6の挙動で確認し、Lock timeoutと停止条件を事前に固定する。
