# PostgreSQL 技術実証アトラス

PostgreSQL 18.6の公開機能について、一次資料、設計判断、再実行可能なLab、運用手順、Evidenceを結び付けるProduct Atlasです。

現在の状態は **`incomplete`** です。個別Labの成功はAtlas全体の完成を意味しません。固定したCoverage Epochに対して全Closureを通過し、生成済みCompletion Certificateが得られるまで`complete`を名乗りません。

## 固定境界

- Normative version: PostgreSQL 18.6 / `REL_18_6`
- Coverage epoch: 2026-08-28
- Compatibility observations: PostgreSQL 17.11、16.15、15.19、14.24
- Development versions: 対象外
- 外部ExtensionとManaged Service固有機能: 完全性の対象外

## 構造

- `atlas/`: Capability、Claim、Proof Obligation、判断、失敗、除外
- `versions/`: Version固定と互換性境界
- `labs/`: SQL、MVCC、Planner、Index、Backup/Recovery、Replication、Upgradeの再実行Harness
- `operations/`: 診断・変更・復旧Runbook
- `evidence/`: 実行結果とCore Evidence Record
- `.agents/skills/postgresql-atlas/`: 一つのRouter Skill
- `evals/`: Routerの挙動評価

## 実行

前提はDocker Engineと`jq`です。Manifest検証には隣接する`reference-atlas-core`の固定Commitを使用します。

```bash
make validate
make test-static
make lab LAB=sql
make lab LAB=mvcc
make lab LAB=planner
make lab LAB=index
make lab LAB=backup-recovery
make lab LAB=replication
make lab LAB=upgrade
make eval
```

Labは`pgra-<lab>-<pid>`という一時Resourceだけを使い、終了時に削除します。失敗時に証拠を調べたい場合は`KEEP_LAB=1`を指定します。

## 完成の意味

`make validate`は共通ManifestのSchema適合を検証します。Atlas全体の完成には、Authority、Coverage、Claim、Execution、Operational、Skill、Publicationの7 Closureすべてが必要です。現時点の未完項目は[docs/STATUS.md](docs/STATUS.md)を参照してください。
