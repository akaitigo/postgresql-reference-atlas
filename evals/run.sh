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
# Regeneration must be byte-identical for the same locked inputs. Runtime
# identity belongs to Lab/Scenario Evidence; this deterministic Skill artifact
# uses the same fixed generation epoch as the definitive routing contract.
generated_at="2026-08-28T00:00:00+09:00"
jq -n --arg generated_at "$generated_at" --argjson results "$results" \
  '{schema_version:1,id:"skill.postgresql-router",atlas_id:"postgresql-reference-atlas",atlas_release:"v1.0.0",skill_id:"postgresql-atlas",generated_at:$generated_at,cases:($results | map({id,category,result:.verdict,assertion:(.id + " は期待したCapability、Coverage、安全境界へ正しくRoutingされる。"),evidence_ids:["skill.router-eval"]}))}' \
  > "$eval_entity"
manifest="$ROOT/evidence/harnesses/skill-router-eval.manifest"
paths_file="$(mktemp)"
find "$ROOT/scripts" "$ROOT/.agents/skills/postgresql-atlas" -type f -print \
  | sed "s#^$ROOT/##" >> "$paths_file"
printf '%s\n' \
  evals/cases.json \
  evals/run.sh \
  evals/postgresql-router.skill-eval.json >> "$paths_file"
: > "$manifest"
while IFS= read -r relative; do
  printf '%s  %s\n' "$(sha256_file "$ROOT/$relative")" "$relative" >> "$manifest"
done < <(LC_ALL=C sort -u "$paths_file")
rm -f "$paths_file"
source_digest="$(sha256_file "$ROOT/sources.lock.yaml")"
environment_digest="$(sha256_file "$ROOT/environments/local.yaml")"
harness_digest="$(sha256_file "$manifest")"
artifact_digest="$(sha256_file "$report")"
artifact_size="$(wc -c < "$report" | tr -d ' ')"
cat > "$ROOT/evidence/skill-router-eval.evidence.yaml" <<EOF
schema_version: 1
id: skill.router-eval
atlas_id: postgresql-reference-atlas
claim_ids: [skill.router]
kind: skill-eval
producer: postgresql-reference-atlas
command: make eval
created_at: "${generated_at}"
environment:
  profile: local
  manifest_digest: sha256:${environment_digest}
source_digest: sha256:${source_digest}
harness_digest: sha256:${harness_digest}
harness_path: evidence/harnesses/skill-router-eval.manifest
artifact:
  uri: evidence/artifacts/skill-router-eval.json
  digest: sha256:${artifact_digest}
  media_type: application/json
  size_bytes: ${artifact_size}
verdict: pass
retention: git
EOF
echo "Router Skill Evalを通過しました: $passed/$total"
ruby "$ROOT/tools/generate-definitive-skill-eval.rb"
ruby "$ROOT/tools/verify-definitive-skill-eval.rb"
