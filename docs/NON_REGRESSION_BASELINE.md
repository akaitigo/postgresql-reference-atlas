# 公開main非後退Baseline

## 正本

公開済み`main`のcommit `8a4259d2de288178b8b87f09a09e5b57654c88e0`を非後退Baselineとする。BaselineはDefinitive Inventory追加前に実査済みだった29 Target、29 Claim、28 Proof、30 Evidence、10 Source、27 Lab、30 Skill Eval Case、CI 27 Lab Matrixを固定する。

加えて、Lab、Test、Harness、Assertion、Evidence Artifact、Source Lock、Skill、Runbookを構成する既存219 FileのSHA-256を`baseline/non-regression-v1.json`へ固定した。加法更新が必要なClaim、Proof、Capabilityの集約Indexは、公開mainの各Entryを完全一致で固定する。追加は許容するが、次は禁止する。

- 削除、skip、xfail、disabled化
- required・covered・合格閾値・Version・Platform・CI Matrixの格下げ
- 既存Target、Claim、Proof、Evidenceの粗い集約またはScope外退避
- 実PostgreSQL Runtime Proofのmock、fixture、static Proofへの置換
- 失敗Evidenceの削除または上書き

## Replacement

置換には旧IDと新ID、equal-or-strongerの理由、同等以上のRuntime実行Proof、Migration Claimへ接続されたMigration Evidenceが必要である。現在承認する変更は次の2件だけである。

1. v1 Completion Certificateをbyte-identicalのまま履歴配置へ移した。
2. CIのCore refをv1互換の子孫commitへ前方更新し、Definitive Gate v2を追加した。

## 現在の差分

非後退Baselineをすべて保持したうえで、Targetは29から56、Claimは29から30、Proofは28から29、Evidenceは30から31、LabとCI Matrixは27から29へ増加した。Sourceと既存Skill Caseは不変である。新しいDefinitive Gapは既存Targetを格下げせず、別の追加Target、Inventory、Verification Matrixへ記録する。

`make non-regression-audit`がBaseline、Mapping、Migration Evidence、現行Repositoryを照合する。結果は`evidence/non-regression-audit-report.json`へ固定する。
