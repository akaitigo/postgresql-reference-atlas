---
name: postgresql-atlas
description: PostgreSQL 18.6の設計、SQL実装、MVCC、Planner、Index、Backup、Recovery、Replication、Upgradeを、一次資料と再実行可能なEvidenceに基づいて判断・診断・検証するときに使う。外部ExtensionやManaged Service固有機能はCoverage Gapとして分離する。
---

# PostgreSQL Atlas Router

このSkillはPostgreSQL知識を複製せず、`postgresql-reference-atlas`のMastery Outcome、Coverage、Claim、Lab、Runbook、Evidenceへ依頼を案内する。

## 最初に確認すること

1. 対象Serverの`server_version`、環境、権限、Topologyを確認する。
2. [Mastery Routing](references/mastery-routing.md)から利用者が求めるOutcomeとSurfaceを選ぶ。
3. [Capability Index](references/capability-index.md)から対象Capabilityと現在のCoverage stateを選ぶ。
4. 技術的主張は`atlas/claims/index.yaml`、一次資料は`sources.lock.yaml`、合格条件は`atlas/proof-obligations/index.yaml`へ戻る。
5. 実行が必要なら対応する`labs/<capability>/`を隔離環境で再実行し、`evidence/*.evidence.yaml`を確認する。

## Mode

- `design`: 判断表、前提、採用条件、不採用条件、代替案を提示する。
- `implement`: 対応LabとProof Obligationを基準に最小変更を実装し、結果不変性も検証する。
- `diagnose`: 既定は読み取り専用。観測事実、原因仮説、反証条件を分ける。
- `recover`: [Safety Boundary](references/safety-boundary.md)を読み、隔離先Restoreと停止条件を先に定める。
- `migrate`: 旧版、新版、Extension、Collation、停止時間、Rollback不能点を固定する。
- `review`: ClaimとEvidenceを辿り、証拠がなければ断定せずCoverage Gapを返す。

## 境界

- 正式対象はPostgreSQL 18.6 / `REL_18_6`。14.24〜17.11は互換性観測、19 Betaは対象外。
- PostGIS、pgvector、外部Pooler、HA製品、Managed Service固有APIはこのAtlasの完全性に含めない。必要なら外部Product AtlasまたはInteroperability Labを提案する。
- 実環境のPromotion、Drop、WAL操作、Replica再構築、PITR、Major Upgradeを承認なしに実行しない。
- Coverage Targetが`partial`なら、実装済み部分と未証明部分を明示し、`complete`と表現しない。
- 8 Outcomeと14 SurfaceはPostgreSQL内の問いを閉じる契約であり、別分野を追加する理由にしない。

決定論的なCapability検索には`scripts/route.sh "<依頼>"`を使える。該当しなければ`coverage-gap`を返す。
