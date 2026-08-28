#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/lib.sh"
name="pgra-definitive-inventory-$$"
capture="$(mktemp)"
source_root="${POSTGRES_SOURCE_ROOT:-/private/tmp/postgresql-rel-18.6-git}"
source_commit="724edf9bde9d356724ad384a2e196edc3c9f80f7"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; rm -f "$capture"; }
trap cleanup EXIT

require_command git
if [[ ! -d "$source_root/.git" ]]; then
  [[ ! -e "$source_root" ]] || die "Git checkoutではないSource pathが存在します: $source_root"
  git clone --filter=blob:none --no-checkout https://github.com/postgres/postgres.git "$source_root"
fi
git -C "$source_root" checkout --detach "$source_commit" >/dev/null
[[ "$(git -C "$source_root" rev-parse HEAD)" == "$source_commit" ]] || die "Source commitがLockと一致しません"

docker run -d --name "$name" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$name"
wait_postgres_database "$name" atlas
docker exec -i "$name" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d atlas \
  < "$ROOT/labs/definitive-inventory/capture.sql" > "$capture"
ruby "$ROOT/tools/generate-definitive-inventory.rb" "$source_root" "$capture"
echo "Definitive Authority Inventoryを生成しました"
