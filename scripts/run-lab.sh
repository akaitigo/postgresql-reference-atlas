#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB="${1:-}"

if [[ ! "$LAB" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]] || [[ ! -x "$ROOT/labs/$LAB/run.sh" ]]; then
  echo "未知または実行不能なLabです: $LAB" >&2
  exit 2
fi

exec bash "$ROOT/labs/$LAB/run.sh"
