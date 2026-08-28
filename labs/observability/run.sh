#!/usr/bin/env bash
set -euo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/run-sql-lab.sh" \
  observability operations.observability test-report \
  -c shared_preload_libraries=pg_stat_statements -c compute_query_id=on
