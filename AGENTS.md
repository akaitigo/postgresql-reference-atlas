# Repository instructions

このRepositoryは`postgresql-reference-atlas`の正本です。

## Language and identity

- 利用者向け文書、Skill、CLIメッセージは日本語を正本にする。
- Schema Key、ID、Repository名、Path、SQL識別子、PostgreSQLの正式名称は英語を維持する。
- Repository IDは`postgresql-reference-atlas`、日本語Titleは`PostgreSQL 技術実証アトラス`とする。

## Canonical chain

`Authority Source -> Coverage Target -> Capability -> Claim -> Proof Obligation -> Lab -> Evidence -> Skill Eval`を維持する。孤立したClaimやEvidenceを追加しない。

`mastery.yaml`は「この分野で答えられるべき問い」の正本であり、既存CoverageやDomain固有Manifestを置き換えない。8 Outcomeと14 Surfaceは既存Target Setへ接続し、件数合わせのために分野やTarget Setを追加しない。

## Version and completion

- このEpochのNormative versionはPostgreSQL 18.6、Source tagは`REL_18_6`。
- Versionや一次資料を更新するときは新しいCoverage Epochを作る。
- 全Gate通過前は`atlas.yaml`の`status: incomplete`を維持する。
- `complete`へ変更する前に`atlas audit .`を通す。
- 未実行のLabを`covered`、未生成Evidenceを`pass`として記録しない。

## Safety

- Failure、Recovery、Replication、Upgrade LabはAtlasが作る隔離Resourceだけを操作する。
- 接続先がHarness生成物であることを確認できない場合は破壊的操作を停止する。
- 実環境に対する診断は既定で読み取り専用とする。

## Rights

- 独自コードと文書はApache-2.0。
- 第三者素材は`third_party/manifest.yaml`へ記録し、一次資料を必要以上に転載しない。
- GitHub公開、Release、外部書込みは明示的な依頼なしに行わない。
