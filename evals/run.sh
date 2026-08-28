#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
router="$ROOT/.agents/skills/postgresql-atlas/scripts/route.sh"
cases="$ROOT/evals/cases.json"
report="$ROOT/evidence/artifacts/skill-router-eval.json"
eval_entity="$ROOT/evals/postgresql-router.skill-eval.json"
mkdir -p "$ROOT/evidence/artifacts"

passed=0
total="$(jq 'length' "$cases")"
results='[]'
while IFS= read -r case_json; do
  id="$(jq -r '.id' <<<"$case_json")"
  input="$(jq -r '.input' <<<"$case_json")"
  actual="$(bash "$router" "$input")"
  verdict=pass
  for field in capability mode outcome coverage safety; do
    expected="$(jq -r ".${field}" <<<"$case_json")"
    observed="$(jq -r ".${field}" <<<"$actual")"
    [[ "$observed" == "$expected" ]] || verdict=fail
  done
  [[ "$(jq -r '.version' <<<"$actual")" == "18.6" ]] || verdict=fail

  capability="$(jq -r '.capability' <<<"$actual")"
  lab="$(jq -r '.lab // empty' <<<"$actual")"
  evidence="$(jq -r '.evidence // empty' <<<"$actual")"
  runbook="$(jq -r '.runbook // empty' <<<"$actual")"
  if [[ "$capability" == "coverage-gap" ]]; then
    [[ -z "$lab" && -z "$evidence" ]] || verdict=fail
  elif [[ "$(jq -r '.coverage' <<<"$actual")" == "planned" ]]; then
    [[ -n "$lab" && -d "$ROOT/$lab" && -z "$evidence" && "$(jq -r '.safety' <<<"$actual")" == "stop" ]] || verdict=fail
    rg -q --fixed-strings "id: $capability" "$ROOT/atlas/capabilities/index.yaml" || verdict=fail
  else
    [[ -n "$lab" && -d "$ROOT/$lab" ]] || verdict=fail
    [[ -n "$evidence" && -s "$ROOT/$evidence" ]] || verdict=fail
    rg -q --fixed-strings "id: $capability" "$ROOT/atlas/capabilities/index.yaml" || verdict=fail
    [[ -z "$runbook" || -s "$ROOT/$runbook" ]] || verdict=fail
  fi

  [[ "$verdict" == "pass" ]] && passed=$((passed + 1))
  case "$id" in
    coverage-gap-*) category=coverage-gap ;;
    evolve-*) category=lifecycle ;;
    delegate-*) category=authorization ;;
    *rls*|*security*) category=security ;;
    verify-catalog-inventory) category=authority ;;
    choose-*|build-domain-type) category=near-neighbor ;;
    operate-*|troubleshoot-*|recover-*|verify-*) category=execution ;;
    *) category=routing ;;
  esac
  results="$(jq -c --arg id "$id" --arg capability "$capability" --arg mode "$(jq -r '.mode' <<<"$actual")" \
    --arg outcome "$(jq -r '.outcome' <<<"$actual")" --arg coverage "$(jq -r '.coverage' <<<"$actual")" \
    --arg safety "$(jq -r '.safety' <<<"$actual")" --arg verdict "$verdict" --arg category "$category" \
    '. + [{id:$id,category:$category,capability:$capability,mode:$mode,outcome:$outcome,coverage:$coverage,safety:$safety,verdict:$verdict}]' <<<"$results")"
done < <(jq -c '.[]' "$cases")

pass_rate="$(awk -v p="$passed" -v t="$total" 'BEGIN { printf "%.3f", p/t }')"
jq -n --argjson total "$total" --argjson passed "$passed" --argjson pass_rate "$pass_rate" \
  --argjson results "$results" \
  '{total:$total,passed:$passed,pass_rate:$pass_rate,version:"18.6",path_checks:true,results:$results,verdict:(if $pass_rate == 1 then "pass" else "fail" end)}' > "$report"
jq -e '.verdict == "pass"' "$report" >/dev/null
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
jq -n --arg generated_at "$generated_at" --argjson results "$results" \
  '{schema_version:1,id:"skill.postgresql-router",atlas_id:"postgresql-reference-atlas",atlas_release:"v1.0.0",skill_id:"postgresql-atlas",generated_at:$generated_at,cases:($results | map({id,category,result:.verdict,assertion:(.id + " は期待したCapability、Coverage、安全境界へ正しくRoutingされる。"),evidence_ids:["skill.router-eval"]}))}' \
  > "$eval_entity"
record_evidence skill-router-eval skill.router skill-eval local "make eval" "$report" pass \
  "$ROOT/evals" skill.router-eval "$ROOT/.agents/skills/postgresql-atlas"
echo "Router Skill Evalを通過しました: $passed/$total"
