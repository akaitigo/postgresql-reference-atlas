# 統合Reference SystemとScenario Proof

`labs/reference-system`はPostgreSQL 18.6の一時Container内で、複数Behaviorが交差する境界を実行するbounded Reference Systemである。個別LabやAuthority由来Atomic behaviorの専用Proofを置き換えない。

## 統合実行

```bash
make lab LAB=reference-system
make scenario-proofs-generate
make scenario-proofs-verify
```

Reference Systemはnormal、boundary、rejection、failure、recovery、migration、operations、security、performance、compatibilityを各1 rowとして実行する。Frontend参照方式の`refusal`は、公開済みPostgreSQL Verification Matrixの非後退IDを維持するため`rejection`へ対応付ける。

`evidence/artifacts/reference-system.json`はPostgreSQL server、psql client、Version契約、固定Container imageを記録する。SQL Harness、`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`、WAL LSN差分、PostgreSQL server log、`pg_stat_statements` metricも別のArtifact pointerとして保持する。`evidence/artifacts/reference-system.server.log`はCredential表現を検査してから保存する。

## Behavior固有Proof

`evidence/scenarios/index.json`は、公開済みVerification Matrixの29 Behavior × 10 Scenarioから290個の専用JSONを列挙し、各File digestを固定する。この29 Behaviorは非後退対象であり、Authority Semantic denominatorではない。Frontendの85 Patternや850 rowという絶対件数はPostgreSQLへ転用しない。

各rowはserver、client、version、runtime identityと、SQL、plan、WAL、log、metric Artifactを独立に評価する。専用Evidenceから確認できる項目だけを`observed`とし、それ以外は理由付き`gap`とする。統合Reference Systemのidentity、log、plan、WAL、metricはCross-behavior参照として全rowへ接続するが、Behavior固有Proofへ昇格しない。現行reportはSecurity 8 rowを固定PostgreSQL/psql runtimeで初回実行し、残り282 rowをgapとして保持する。version compatibilityは14.24〜18.6、pg_upgradeは17.11→18.6を専用runtimeで検証する。

Scenario gapは、対象SurfaceとScenarioの全Variantを専用の実PostgreSQL server/psql clientで駆動し、各Variantのretry countが0、専用Oracleがexpected/pass、Source/Harness digest、および同一専用実行に由来するSQL/plan/WAL/log/metric Artifactがすべて揃った場合だけ閉じる。既存69 rowのEvidence対応は補助的なbounded observationとして保持する。統合Systemの結果や別Evidence Artifactのmetadataは不足項目へ流用しない。`evidence/scenarios/closure-plan.json`はSecurityから始まるrisk順で未Closure rowを最大4 row/trancheへ分割し、FEの絶対件数を転用しない。

専用runは全Artifactを同一Filesystem上のstaging directoryへ生成し、full-run pass後だけdirectory renameでpublishする。失敗runは直前成功Evidenceを保持し、swap失敗はrollbackする。部分上書き、新旧世代混在、失敗runによる成功Evidence消去は`make scenario-evidence-atomicity-test`で拒否する。

## 完了境界

現時点のAuthority Review Queueは全件`pending-human`で、昇格済みAtomic behaviorは0件である。このため専用Runtime closure済み8 rowも`completion_eligible: false`であり、残り282 rowはScenario gapを維持する。Reference Systemが10/10を通っても、Authority Human review、全Variantの専用実行、Behavior固有identity/Artifact gap、全PostgreSQL SurfaceのProofが閉じるまでRepository statusは`incomplete`である。
