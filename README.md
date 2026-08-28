# PostgreSQL 技術実証アトラス

PostgreSQL 18.6の公開機能について、一次資料、設計判断、再実行可能なLab、運用手順、Evidenceを結び付けるProduct Atlasです。

このAtlasのMastery Promiseは、PostgreSQLについて「理解する、選ぶ、構築する、検証する、運用する、診断する、進化させる、Agentへ委任する」の8 Outcomeを、14の技術Surfaceにわたって一次資料と実行証拠へ接続することです。対象分野を増やす契約ではありません。

現在のDefinitive再監査状態は **`incomplete`** です。v1の29 Targetに対するCompletion Certificateはbounded historicalとして保持しますが、Product全SurfaceのClosure証明としては扱いません。Definitive Gate v2で公式Surface Inventory、Target別Proof、統合Reference System、方式比較、運用演習、Skill Evalが閉じるまで再昇格しません。

公開mainの既存Test、Lab、Target、Claim、Proof、Evidence、Source、Skill Eval、CI Matrixは[非後退Baseline](docs/NON_REGRESSION_BASELINE.md)として固定し、Definitive作業はこの集合を削らず加法的に進めます。

## 固定境界

- Normative version: PostgreSQL 18.6 / `REL_18_6`
- Coverage epoch: 2026-08-28
- Compatibility observations: PostgreSQL 17.11、16.15、15.19、14.24
- Development versions: 対象外
- PostGIS・pgvector等の外部ExtensionとManaged Service固有機能: 隣接Subject。Core同梱Extension機構とClient-facing Surfaceは対象内

## 構造

- `atlas/`と`claims/`: Capability、集約索引、Core v1 Claim実体
- `authority/`と`surface.inventory.yaml`: Docs、固定Source commit、Runtime Catalogから抽出したDefinitive v2 Inventory
- `authority/locator-extraction.snapshot.json`と`authority/locator-draft/`: 一次資料locatorのURL、metadata、digest、byte offset。第三者本文と抜粋は保存しない
- `authority/body-inventory.snapshot.json`と`authority/body-inventory-draft/`: unique documentと固定raw selectorで列挙したpending-human anchor。Human decision前はSurface/Behavior/Depth実績に算入しない
- `authority/review-queue.snapshot.json`と`authority/review-queue-draft/`: stable raw anchor 5,512件を完全接続したHuman review queue。priority、cluster、batchは作業提案でありSemantic判断ではない
- `authority/reviews/decisions.json`: 一次資料を人が確認したreviewer/time/reason/digest/locator/mapping/resultを記録する必須の昇格経路。初期状態はdecision 0件
- `gaps/claims/`と`verification.matrix.yaml`: 未Closureの提案ClaimとScenario別Gap
- `mastery.yaml`: 8 Outcomeと14 Surfaceを既存Coverageへ接続する契約
- `versions/`: Version固定と互換性境界
- `labs/`: 29領域のVersion固定・再実行可能Harness
- `surface/`: PostgreSQL 18.6公式SQL Command 183件の有限Inventory
- `operations/`: 診断・変更・復旧Runbook
- `evidence/`: 実行結果とCore Evidence Record
- `.agents/skills/postgresql-atlas/`: 一つのRouter Skill
- `evals/`: 既存30 Case、8 Outcome × 14 Surface、停止境界、全Target state、独立Agent Forward Evalの機械記録

## 実行

前提はDocker Engineと`jq`です。Manifest検証には隣接する`reference-atlas-core`の固定Commitを使用します。

```bash
make validate
make audit
make non-regression-audit
make authority-body-non-regression-audit
make authority-body-verify
make authority-review-verify
make definitive-skill-eval-verify
make definitive-audit
make definitive-gate  # incomplete中は昇格拒否が正しい結果
make lab LAB=sql
make lab LAB=types-constraints
make lab LAB=deadlock
make lab LAB=pitr
make lab LAB=logical-replication
make lab LAB=pg-upgrade
make eval
```

`scripts/static-gates.sh`はv1 Certificateに束縛された歴史Harnessとして変更せず保持する。Definitive移行中の現行Graphは`make audit`と`make definitive-audit`で検証する。

利用可能なLabは`authority-lock`、`definitive-inventory`、`sql-surface`、`sql`、`types-constraints`、`catalog-inventory`、`partitioning`、`extension`、`security`、`mvcc`、`locking`、`deadlock`、`planner`、`statistics`、`index`、`performance`、`wal`、`backup-recovery`、`pitr`、`replication`、`logical-replication`、`observability`、`maintenance`、`failure-injection`、`migration`、`upgrade`、`pg-upgrade`、`compatibility-matrix`、`reference-system`です。

Labは`pgra-<lab>-<pid>`という一時Resourceだけを使い、終了時に削除します。失敗時に証拠を調べたい場合は`KEEP_LAB=1`を指定します。

## 完成の意味

`make validate`は既存Manifest、Claim、Evidenceを検証し、`make definitive-audit`はDefinitive v2 InventoryとProof Gap、`make depth-parity-audit`はFE Depth Referenceの18軸、`make parity-audit`は15技術分野の実行深度を機械監査します。v1の実査結果は失効させず、Definitive昇格に足りない部分だけをGapとして公開します。監査結果は[docs/STATUS.md](docs/STATUS.md)を参照してください。
