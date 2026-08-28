# Mastery Routing

`mastery.yaml`を正本とし、依頼を次のOutcomeへ分類してからCapabilityを選ぶ。

| Outcome | 依頼の意図 | 主なRouter Mode |
|---|---|---|
| `understand` | 原理、仕組み、境界を説明する | `review` |
| `choose` | 条件とTrade-offから方式を選ぶ | `design` |
| `build` | SQL、Schema、Clusterを実装する | `implement` |
| `verify` | ClaimをTestとEvidenceで検証する | `review` |
| `operate` | 観測、容量、定常運用を扱う | `diagnose` |
| `troubleshoot` | 劣化、競合、障害を診断・回復する | `diagnose` / `recover` |
| `evolve` | Migration、Upgrade、廃止を扱う | `migrate` |
| `delegate` | Agentへ委任し結果をReviewする | `review` |

14 Surfaceは別分野ではない。PostgreSQLのScope、原理、設計、実装、試験、障害、運用、Security、性能、互換性、移行、比較、来歴、Skillという問いの面を表す。Coverageが`partial`なら、そのOutcomeを完全に満たすと断定しない。
