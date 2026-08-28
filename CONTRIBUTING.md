# Contribution Guide

利用者向け文書は日本語、機械識別子は英語で記述します。変更はAuthority Source、Coverage Target、Capability、Claim、Proof Obligation、Lab、Evidenceの接続を維持してください。

ContributionにはDeveloper Certificate of Origin 1.1への同意を示す`Signed-off-by`をCommitへ追加してください。

```bash
git commit -s
```

Pull Request前に次を実行します。

```bash
make validate
make test-static
make eval
```

新しい技術的主張には一次資料、反証可能な合格条件、再実行可能なEvidenceを追加します。未実行のTestを`pass`、部分対応を`complete`として記録しないでください。
