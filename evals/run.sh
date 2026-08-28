#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
router="$ROOT/.agents/skills/postgresql-atlas/scripts/route.sh"
cases="$ROOT/evals/cases.json"
report="$ROOT/evidence/artifacts/skill-router-eval.json"
mkdir -p "$ROOT/evidence/artifacts"

passed=0
total="$(jq 'length' "$cases")"
results='[]'
while IFS= read -r case_json; do
  id="$(jq -r '.id' <<<"$case_json")"
  input="$(jq -r '.input' <<<"$case_json")"
  expected_capability="$(jq -r '.capability' <<<"$case_json")"
  expected_mode="$(jq -r '.mode' <<<"$case_json")"
  actual="$(bash "$router" "$input")"
  actual_capability="$(jq -r '.capability' <<<"$actual")"
  actual_mode="$(jq -r '.mode' <<<"$actual")"
  verdict=fail
  if [[ "$actual_capability" == "$expected_capability" && "$actual_mode" == "$expected_mode" ]]; then
    verdict=pass
    passed=$((passed + 1))
  fi
  results="$(jq -c --arg id "$id" --arg capability "$actual_capability" --arg mode "$actual_mode" --arg verdict "$verdict" '. + [{id:$id,capability:$capability,mode:$mode,verdict:$verdict}]' <<<"$results")"
done < <(jq -c '.[]' "$cases")

pass_rate="$(awk -v p="$passed" -v t="$total" 'BEGIN { printf "%.3f", p/t }')"
jq -n --argjson total "$total" --argjson passed "$passed" --argjson pass_rate "$pass_rate" \
  --argjson results "$results" \
  '{total:$total,passed:$passed,pass_rate:$pass_rate,results:$results,verdict:(if $pass_rate >= 0.9 then "pass" else "fail" end)}' > "$report"
jq -e '.verdict == "pass"' "$report" >/dev/null
record_evidence skill-router-eval skill.router skill-eval local "make eval" "$report" pass \
  "$ROOT/evals" skill.router-eval
echo "Router Skill Evalを通過しました: $passed/$total"
