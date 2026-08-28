#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/lib.sh"
require_command ruby

artifact="$ROOT/evidence/artifacts/sql-surface.json"
ruby "$ROOT/tools/verify-sql-surface.rb" "$artifact"
record_evidence sql-surface query.sql-surface conformance local "make lab LAB=sql-surface" "$artifact" pass
echo "SQL Command Surface Inventoryを検証しました"
