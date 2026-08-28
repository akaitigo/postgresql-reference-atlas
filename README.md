# PostgreSQL 技術実証アトラス

PostgreSQL 18.6の公開機能について、一次資料、設計判断、再実行可能なLab、運用手順、Evidenceを結び付けるProduct Atlasです。

このAtlasのMastery Promiseは、PostgreSQLについて「理解する、選ぶ、構築する、検証する、運用する、診断する、進化させる、Agentへ委任する」の8 Outcomeを、14の技術Surfaceにわたって一次資料と実行証拠へ接続することです。対象分野を増やす契約ではありません。

現在の状態は **`complete`** です。個別Labの成功ではなく、固定したCoverage Epochに対する全Closure、Claim↔Evidence Graph、Skill Eval、Supply Chain、Completion CertificateをCore v1で監査して完成を判定します。

## 固定境界

- Normative version: PostgreSQL 18.6 / `REL_18_6`
- Coverage epoch: 2026-08-28
- Compatibility observations: PostgreSQL 17.11、16.15、15.19、14.24
- Development versions: 対象外
- 外部ExtensionとManaged Service固有機能: 完全性の対象外

## 構造

- `atlas/`と`claims/`: Capability、集約索引、Core v1 Claim実体
- `mastery.yaml`: 8 Outcomeと14 Surfaceを既存Coverageへ接続する契約
- `versions/`: Version固定と互換性境界
- `labs/`: 27領域のVersion固定・再実行可能Harness
- `surface/`: PostgreSQL 18.6公式SQL Command 183件の有限Inventory
- `operations/`: 診断・変更・復旧Runbook
- `evidence/`: 実行結果とCore Evidence Record
- `.agents/skills/postgresql-atlas/`: 一つのRouter Skill
- `evals/`: Routerの挙動評価

## 実行

前提はDocker Engineと`jq`です。Manifest検証には隣接する`reference-atlas-core`の固定Commitを使用します。

```bash
make validate
make audit
make test-static
make lab LAB=sql
make lab LAB=types-constraints
make lab LAB=deadlock
make lab LAB=pitr
make lab LAB=logical-replication
make lab LAB=pg-upgrade
make eval
```

利用可能なLabは`authority-lock`、`sql-surface`、`sql`、`types-constraints`、`catalog-inventory`、`partitioning`、`extension`、`security`、`mvcc`、`locking`、`deadlock`、`planner`、`statistics`、`index`、`performance`、`wal`、`backup-recovery`、`pitr`、`replication`、`logical-replication`、`observability`、`maintenance`、`failure-injection`、`migration`、`upgrade`、`pg-upgrade`、`compatibility-matrix`です。

Labは`pgra-<lab>-<pid>`という一時Resourceだけを使い、終了時に削除します。失敗時に証拠を調べたい場合は`KEEP_LAB=1`を指定します。

## 完成の意味

`make validate`はManifest、Claim、Evidence、Skill Eval、Provenance、Certificateを検証し、`make audit`はCore v1の完全監査を実行します。Authority、Coverage、Claim、Execution、Operational、Skill、Publicationの7 ClosureはすべてCompletion Certificateへ固定されています。監査結果は[docs/STATUS.md](docs/STATUS.md)を参照してください。
