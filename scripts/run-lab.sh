#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB="${1:-}"

case "$LAB" in
  sql|mvcc|planner|index|backup-recovery|replication|upgrade) ;;
  *)
    echo "使い方: scripts/run-lab.sh {sql|mvcc|planner|index|backup-recovery|replication|upgrade}" >&2
    exit 2
    ;;
esac

exec bash "$ROOT/labs/$LAB/run.sh"
