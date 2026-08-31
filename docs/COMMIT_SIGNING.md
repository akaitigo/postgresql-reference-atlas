# Commit署名契約

Checkpoint commitはDCOの`Signed-off-by`に加え、SSH暗号署名を必須とする。公開鍵は`.github/allowed_signers`へ固定し、秘密鍵や絶対pathはRepositoryへ保存しない。

検証は次で行う。

```bash
make commit-signature-verify
```

ローカルで引数なしの`git verify-commit HEAD`を使う場合は、Repository local configの`gpg.ssh.allowedSignersFile`を`.github/allowed_signers`へ向ける。CIはpush eventのcheckout SHAに対して同じ公開鍵契約を検証し、pull request用の一時merge commitには適用しない。
