# FE Parity監査

`postgresql-depth-parity.yaml`は`frontend-behavior-atlas` commit `4a0b2df8e2091a963bd0e0e1bbccef9c84b49a45`の`FE_DEPTH_REFERENCE.json`、参照契約、4 fixture、非後退baselineをDigest固定し、18軸をPostgreSQL固有denominatorへ写像する。FrontendのTarget/Lab/Test件数は閾値に使わない。

`fe-parity.matrix.yaml`は上記を補助し、PostgreSQLの15技術分野を8観測軸で判定する。Authority由来Behavior/Variant、実Runtime、Artifact path、障害・回復、方式比較、統合System、Skill Evalを分野別に検査する。

`make depth-parity-audit`はFE正本のcommit/file lock、18軸の順序・criterion・PostgreSQL denominator、Gap状態を検証し、`evidence/postgresql-depth-parity-report.json`へ書く。`make parity-audit`はEvidenceのArtifact digestと指定JSON pathを検証し、結果を`evidence/fe-parity-audit-report.json`へ書く。構造やArtifactが不正なら失敗し、正しい未Closureは`incomplete`として残す。

Authority locatorの参照設計は`frontend-behavior-atlas` commit `cabf687bab769b17928d950acc416f3f77eb4ca3`に固定する。`authority/locator-extraction.snapshot.json`と`authority/locator-draft/`は第三者本文・抜粋・引用を保存せず、Source URL、metadata、document/context digest、byte offsetだけを保持する。`make authority-locator-verify`は本文field混入と集計の過大評価を拒否する。

Authority denominatorの参照はFE commit `841ec2fa399606a10305021a8bcd396713b8cee5`、Human review queueの参照は`de2f016b8b44ea67afdb08c0552044807505984e`である。PostgreSQL側はREL_18_6のunique SGML documentとCOPYRIGHT、未取得Source rootを母集団とし、`document-root`と`sgml-id-attribute`の固定selectorでraw anchor候補を列挙する。全anchorはstable IDのReview Queueへ接続し、Human decision後に明示昇格されるまでSemantic Surface、Atomic behavior、Depth達成に算入しない。priority、cluster、batchは作業提案に限る。

Skill Evalの参照はFE commit `8a9e34a89a55cc53702032783c06ede7246a286f`である。PostgreSQL側は8 Outcome × 14 Surfaceを全56 Target state、実Evidence、Authority、Variant、共有Reference Systemのquery plan/WAL/18.6 runtimeへ接続し、mutation authorization、人手Authority、stale relock、曖昧・未知Queryを停止境界として検証する。112 Cellのcontract passはTargetまたはSubject completionへ算入しない。

## 現在値

- FE Depth軸: 18（satisfied 1 / partial 17 / missing 0）
- satisfied: 非後退Gateのみ
- PostgreSQL raw denominator: unique document 398 / raw anchor 5,512 / pending-human 5,512 / Human reviewed 0 / promoted Surface 0 / promoted Atomic behavior 0
- Review queue: 5,512/5,512 anchor / 255 batch / stale hold 0 / unavailable hold 8 / Human decision 0
- 既存生成mapping: 11,340候補 / Variant ID 0 / Runtime Proof接続候補29。Semantic Surface実績には非算入
- 分野: 15
- Gapを持つ分野: 15
- 未Closure軸: 29
- 統合Reference System: RLS、Partition、Index Plan、Lock拒否/回復、WAL、Statement metricのRuntime Sliceを実行済み
- Depth Parity契約: `depth.parity.yaml`の`completion_status: incomplete`、rows 0
- Authority locator: 生成候補11,340 / stale 0 / URL再取得deferred 183 / Human review 0
- Core Authority root: matched 0 / stale 0 / fetch failed 10 / locator deferred 10 / Human review 0 / eligible 0
- Authority本文全体exhaustive: false / PostgreSQL Authority denominator closed: false
- Authority body専用非後退: baseline anchor 5,512 / retained 5,512 / replaced 0 / added 0 / pass
- Skill routing: 112/112 contract pass / bounded evidence route 72 / routing gap 40 / Target state covered 29・partial 16・planned 11 / completion credit false

統合Sliceは単独Artifact内で複数Surfaceを再現するが、Authority raw anchorのHuman review、昇格後Atomic behaviorの専用Target/Claim/Proof、10 Scenario、方式比較、Backup/PITR/Replication/Upgrade統合、Skill全Surfaceを閉じない。このためSubject Gateの判定には使用しない。
