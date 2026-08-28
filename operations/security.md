# Role・認証・RLS安全Review

## Review順序

1. Login RoleとGroup Roleを分離し、`NOSUPERUSER`、`NOCREATEDB`、`NOCREATEROLE`を既定にする。
2. `pg_hba_file_rules`で適用順、接続元、Database、Role、認証方式を確認する。
3. Password verifierがSCRAM-SHA-256であることを確認し、CredentialをEvidenceへ保存しない。
4. Object privilege、Default privilege、Schema `CREATE`、Function `EXECUTE`、Sequence権限を列挙する。
5. RLSは非Owner・非Superuserの独立Sessionから`USING`と`WITH CHECK`を試験する。
6. `SECURITY DEFINER`は完全修飾名または固定`search_path`を使い、PUBLIC実行権限をReviewする。

TLS終端、証明書検証、Secret rotation、監査要件は配備環境の責任境界と併記する。このAtlasのSCRAM/RLS Labだけで通信路暗号化を証明したとは扱わない。
