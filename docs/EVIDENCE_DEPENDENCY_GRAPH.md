# Evidence Dependency Graph

`evidence/dependency-graph.json`は、PostgreSQL AtlasのEvidenceを、そのEvidenceを生成した入力とfirst-attempt実行へ結ぶ機械可読Graphです。Coreは正式main/CI成功commit `072d7ca77981f51754e824d70c6d4ecd55ea67e5`へ固定しています。

入力はPostgreSQL固有のAuthority/契約、SQL・Schema・Correctness Harness、Concurrency/MVCC、WAL/Replication/Backup、Migration/Compatibility、Operations/Performance/Recovery、Scenario/Skill Reporter、PostgreSQL server/client runtime、およびlocal/container/cluster profileから構成します。Frontendの件数は分母へ転用しません。

`ruby tools/rerun-evidence-dependencies.rb`は、既存29 Lab、Skill Eval、静的Gate、専用Scenario Runtime、Scenario Proof、Closure Plan、Provenanceを各1回だけ実行します。実行はRepositoryの一時copyで行い、入力digest不変・既存file削除なし・Evidence範囲外変更なしを確認した後だけ、変更された生成物を公開します。途中失敗時は現在の成功世代を保持し、公開途中の失敗時は退避世代からrollbackします。Runtime Lab/Scenarioの時刻は実行時刻を記録し、静的GateとProvenanceだけは同じfull-run ledgerの開始時刻を用いて固定入力からbyte deterministicに生成します。

正本順序は、全tracked generator（監査Report、静的Gate、Eval、Scenario Proof、Closure Plan、Provenance）を依存順に先に実行し、full-run ledgerが全Evidence/Artifact/Eval/Provenance出力へ結ばれていることを検証し、最後にGraphを1回生成する順序です。静的Gateが更新するEvidenceをEvalより先に確定するため、Eval内のEvidence bindingも後段でstaleになりません。Graph生成後はverify、Core audit、freshness、clean checkだけを実行します。Graph自身のdigestも最後の生成時にledgerへ結び、ledgerとGraphはrollback付きの同一publish操作で更新します。

`make evidence-pipeline-refresh`はderived generator→ledger verify→final Graphを直列実行し、`make evidence-pipeline-clean`は後段Gateを含む再実行でtracked出力に差分がないことを確認します。generator binding省略、Graph後のEvidence mutation、Graph digestだけの書換え、Eval refresh省略はnegative fixtureで拒否します。

必要outputはCoreの既知Evidence探索に加えて、PostgreSQLの全Lab artifact、harness manifest、Scenario trace/observationをRepositoryから機械列挙します。input変更後は依存outputを実再実行し、現在digest、runtime identity、first-attempt結果へ結ぶまでcurrentにできません。digestだけの更新、output漏れ、Evidenceの退避、Scenario Proof/Closure Plan構造縮小はnegative fixtureで拒否します。

検証Command:

```sh
ruby tools/verify-evidence-dependency-graph.rb
ruby tools/test-evidence-dependency-graph.rb
make core-evidence-dependency-audit
make evidence-pipeline-clean
```
