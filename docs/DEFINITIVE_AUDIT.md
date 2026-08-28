# PostgreSQL Subject Definitive 独立再監査

## 判定

`postgresql-reference-atlas`はv1の有限Coverageに対して有効なbounded Completionを持つが、PostgreSQL 18.6 ProductのSubject Definitiveとは未確認である。Definitive昇格は保留し、`atlas.yaml`を`incomplete`へ戻した。

履歴Certificateは`evidence/history/v1.0.0/completion-certificate.json`へ不変保存した。このCertificateが証明するのはv1の29 Target、30 Evidence、27 Labであり、Definitive v2の11,340 Inventory項目ではない。

## Authority Inventory

次の一次資料から機械抽出した。

- PostgreSQL 18.6公式SQL Command索引
- PostgreSQL REL_18_6固定commitの公式SGML 170章・4,133節、219 Reference File、Protocol節、54同梱Extension Control
- Digest固定PostgreSQL 18.6 Runtimeのpg_catalog、information_schema、pg_settings、pg_available_extensions

主要件数はFunction 3,403、Type/Collation 1,536、Operator 800、GUC 400、SQL CommandのDocs/Source照合347、Cast 236、System Catalog 214、ExtensionのSource/Runtime照合115、Client-facing Reference 57、Protocol節46である。重複Authority Viewは同じ対象をDocs・Source・Runtime間で照合するため保持する。

11,340項目は56 Coverage Targetへ自動分類したmapping候補であり、Semantic Surface、Atomic behavior、Depth達成件数ではない。Authority母集団は別途、unique document 398件からfixed selectorでraw anchor 5,512件を抽出し、stable IDのReview Queue 255 batchへ全件接続する。全件`pending-human`で、Human review後に明示的に昇格されるまでSurface/Behaviorとして扱わない。queue件数、priority、cluster、batchもDepth達成へ算入しない。

## Proof Gap

Definitive v2ではBehaviorごとに専用Claim、Scenarioごとに専用Proof・Evidence・Artifactを要求する。v1の集約Claimと代表Labは69 Scenario Rowへ再利用できるが、正常、境界、拒否、障害、回復、運用、安全性、性能、互換性、移行の必要集合を閉じない。

現在のGapは次の通り。

- 56 required Target中55 TargetがDefinitive未Closure
- 5,512 raw anchor候補は全件pending-humanで、Human-reviewed/promoted SurfaceとAtomic behaviorは0件
- 11,340自動mapping候補中11,320件は専用covered Target・accepted Claimの組を持たない
- 全Scenario分類113,400 Row中113,331 Rowが未作成。Surfaceから必須となる43,544 Scenarioのうち43,510 Rowが未接続
- Subject全体として、必要Scenarioごとの専用Proof・Evidence・Artifact closureが未整備
- Function、Operator、Cast、GUC、Protocol、Client Toolの全件Proofが未実装
- Authentication、Resource Limit、Corruption Recoveryが未実装
- 統合Reference SystemのSecurity、Partition、Planner、Lock、WAL、Observability Sliceは実行済み。Backup/PITR/Replication/Upgrade統合、複数方式Comparison、Runbook実地演習は未実装
- Definitive Skill Evalは8 Outcome × 14 Surfaceを全件評価し、mutation authorization、人手Authority/stale relock、曖昧・未知Queryをfail-closedで停止する。112 Cellはcontract passだが72 bounded evidence route / 40 routing gapで、全56 Targetはcovered 29 / partial 16 / planned 11のまま記録する
- 現行Definitive Certificateは未発行

## Boundary

PostGIS、pgvector等の外部Extension、Managed Service固有API、外部HA Orchestratorは隣接Subjectとする。一方、PostgreSQL Coreに含まれるExtension機構、Frontend/Backend Protocol、Client Utility、Authentication、Streaming/Logical Replication、Failover前後のCore責任、Resource Limit、Corruption検出、Upgrade Toolは除外しない。

## Promotion rule

`make definitive-audit`はInventoryの未分類0とGap計数を検証する。`make parity-audit`は15分野の実行証拠と未Closure軸を検証する。`make definitive-gate`は全required Target、専用Claim/Evidence、113,400 RowのScenario Matrix、実Runtime、全Behaviorを接続する統合Reference System、方式比較、Definitive Skill Eval、Certificateが揃うまで成功してはならない。
