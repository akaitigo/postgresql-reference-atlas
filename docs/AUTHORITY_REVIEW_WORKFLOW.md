# Authority anchor review workflow

`authority/review-queue.snapshot.json`は、固定済みPostgreSQL Authority bodyから列挙した5,512 raw anchorを、人が一次資料を確認できる255 batchへ分割した作業queueである。queue件数、priority、candidate cluster、batchはSurface分類やDepth達成を表さない。全anchorはdecisionが記録されるまで`pending-human`である。

各itemはstable `anchor_id`、document/source identity、locked body digest、inventory/review tool digest、locator、固定本文内のbyte offsetとcontext digestを保持する。第三者本文・抜粋・見出しは保存しない。priority 0は既存の自動生成mapping候補とのlocator一致、priority 1はSGML ID、priority 2はdocument構造を示すレビュー順の提案に限る。clusterとbatchにもSemantic判断能力はない。

stale documentは`stale_holds`へ隔離し、Sourceの再取得、digest再固定、Body Inventory再生成が完了するまでqueueへ入れない。取得不能documentは`unavailable_holds`へ保持する。現状はstale 0、unavailable 8である。

人はbatch itemの`authority_url`、`document_locator`、`locator`を用いて固定commitの一次資料を確認し、`authority/reviews/decisions.json`へinclude、exclude、merge、splitを記録する。各decisionには次を必須とする。

- 一意なdecision IDと対象anchor ID
- queue itemと完全一致するdocument、source/tool digest、locator、offset、context digest binding
- 40文字以上の理由、人のreviewer、ISO date-time、`manual-primary-source`
- 全旧anchorを覆う旧ID→新ID mapping
- mapping先と完全一致するSurface／Atomic behavior result

自動処理、Agent、priority、cluster、batchだけをreviewerまたはSemantic判断にできない。同じanchorへの複数decision、binding drift、mapping/result不一致は検証を失敗させる。decision後も未処理anchor、stale hold、unavailable holdが残る間は`incomplete-human-review-required`と`authority_semantics_exhaustive: false`を維持する。

```sh
ruby tools/generate-authority-review-queue.rb
make authority-review-verify
```
