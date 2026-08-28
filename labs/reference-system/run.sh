#!/usr/bin/env bash
set -euo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/run-sql-lab.sh" \
  reference-system foundation.reference-system.runtime-slice test-report \
  postgres -c shared_preload_libraries=pg_stat_statements
