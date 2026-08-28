# Lock Lab

`dblink`の独立SessionでRow Lockを保持し、競合Sessionの`NOWAIT`がSQLSTATE `55P03`で拒否され、解放後に更新できることを検証します。
