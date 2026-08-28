# FE Parity監査

`postgresql-depth-parity.yaml`は`frontend-behavior-atlas` commit `4a0b2df8e2091a963bd0e0e1bbccef9c84b49a45`の`FE_DEPTH_REFERENCE.json`、参照契約、4 fixture、非後退baselineをDigest固定し、18軸をPostgreSQL固有denominatorへ写像する。FrontendのTarget/Lab/Test件数は閾値に使わない。

`fe-parity.matrix.yaml`は上記を補助し、PostgreSQLの15技術分野を8観測軸で判定する。Authority由来Behavior/Variant、実Runtime、Artifact path、障害・回復、方式比較、統合System、Skill Evalを分野別に検査する。

`make depth-parity-audit`はFE正本のcommit/file lock、18軸の順序・criterion・PostgreSQL denominator、Gap状態を検証し、`evidence/postgresql-depth-parity-report.json`へ書く。`make parity-audit`はEvidenceのArtifact digestと指定JSON pathを検証し、結果を`evidence/fe-parity-audit-report.json`へ書く。構造やArtifactが不正なら失敗し、正しい未Closureは`incomplete`として残す。

Authority locatorの参照設計は`frontend-behavior-atlas` commit `cabf687bab769b17928d950acc416f3f77eb4ca3`に固定する。`authority/locator-extraction.snapshot.json`と`authority/locator-draft/`は第三者本文・抜粋・引用を保存せず、Source URL、metadata、document/context digest、byte offsetだけを保持する。`make authority-locator-verify`は本文field混入と集計の過大評価を拒否する。

## 現在値

- FE Depth軸: 18（satisfied 1 / partial 17 / missing 0）
- satisfied: 非後退Gateのみ
- PostgreSQL denominator: Authority Behavior 11,340 / Variant ID 0 / Runtime Proof接続Behavior 29 / 専用accepted Claim未接続11,320
- 分野: 15
- Gapを持つ分野: 15
- 未Closure軸: 29
- 統合Reference System: RLS、Partition、Index Plan、Lock拒否/回復、WAL、Statement metricのRuntime Sliceを実行済み
- Depth Parity契約: `depth.parity.yaml`の`completion_status: incomplete`、rows 0
- Authority locator: 生成候補11,340 / stale 0 / URL再取得deferred 183 / Human review 0
- Core Authority root: matched 0 / stale 0 / fetch failed 10 / locator deferred 10 / Human review 0 / eligible 0
- Authority本文全体exhaustive: false / PostgreSQL Authority denominator closed: false

統合Sliceは単独Artifact内で複数Surfaceを再現するが、全Authority Behaviorの専用Target/Claim/Proof、10 Scenario、方式比較、Backup/PITR/Replication/Upgrade統合、Skill全Surfaceを閉じない。このためSubject Gateの判定には使用しない。
