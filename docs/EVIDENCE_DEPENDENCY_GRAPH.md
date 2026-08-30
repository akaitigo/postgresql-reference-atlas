# Evidence Dependency Graph

`evidence/dependency-graph.json`は、PostgreSQL AtlasのEvidenceを、そのEvidenceを生成した入力とfirst-attempt実行へ結ぶ機械可読Graphです。Coreは正式main/CI成功commit `072d7ca77981f51754e824d70c6d4ecd55ea67e5`へ固定しています。

入力はPostgreSQL固有のAuthority/契約、SQL・Schema・Correctness Harness、Concurrency/MVCC、WAL/Replication/Backup、Migration/Compatibility、Operations/Performance/Recovery、Scenario/Skill Reporter、PostgreSQL server/client runtime、およびlocal/container/cluster profileから構成します。Frontendの件数は分母へ転用しません。

`ruby tools/rerun-evidence-dependencies.rb`は、既存29 Lab、静的Gate、Skill Eval、専用Scenario Runtime、Scenario Proof、Closure Plan、Provenanceを各1回だけ実行します。実行はRepositoryの一時copyで行い、入力digest不変・既存file削除なし・Evidence範囲外変更なしを確認した後だけ、変更された生成物を公開します。途中失敗時は現在の成功世代を保持し、公開途中の失敗時は退避世代からrollbackします。Graph生成器はledgerの入力digestが現在値と一致しない場合に停止します。

Skill Evalの正本順序は`make eval-evidence-dependency-refresh`で、固定入力からbyte deterministicなEvalを生成し、Graphをfull rerun ledgerのoutput bindingへ再固定してから検証します。Graph refresh省略とEval outputだけの改ざん／digest書換えはnegative fixtureで拒否します。commit後は`make eval-evidence-dependency-clean`により、この順序を再実行してもtracked Eval/Graphに差分がないことを確認します。

必要outputはCoreの既知Evidence探索に加えて、PostgreSQLの全Lab artifact、harness manifest、Scenario trace/observationをRepositoryから機械列挙します。input変更後は依存outputを実再実行し、現在digest、runtime identity、first-attempt結果へ結ぶまでcurrentにできません。digestだけの更新、output漏れ、Evidenceの退避、Scenario Proof/Closure Plan構造縮小はnegative fixtureで拒否します。

検証Command:

```sh
ruby tools/verify-evidence-dependency-graph.rb
ruby tools/test-evidence-dependency-graph.rb
make core-evidence-dependency-audit
```
