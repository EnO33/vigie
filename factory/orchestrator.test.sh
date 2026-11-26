#!/usr/bin/env bash
# Tests de la sélection du travail prêt dans factory/orchestrator.sh.
#   bash factory/orchestrator.test.sh
# Un gh factice applique les --label (en ET, comme gh) puis le filtre --jq sur un jeu d'issues
# fixe : on vérifie l'ordre de prise en charge et le compteur WIP.
set -uo pipefail

ORCH="$(cd "$(dirname "$0")" && pwd)/orchestrator.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
# gh factice : « gh issue list … --label A --label B --jq EXPR » sur $GH_FIXTURE.
labels=(); expr='.'
while [ $# -gt 0 ]; do
  case "$1" in
    --label) labels+=("$2"); shift 2 ;;
    --jq) expr="$2"; shift 2 ;;
    *) shift ;;
  esac
done
data="$(cat "$GH_FIXTURE")"
for l in "${labels[@]}"; do
  data="$(jq --arg l "$l" '[.[] | select([.labels[].name] | index($l))]' <<<"$data")"
done
jq -r "$expr" <<<"$data"
EOF
chmod +x "$TMP/bin/gh"

# Issues ouvertes : numéro puis labels.
issue() { local n="$1"; shift; jq -n --argjson n "$n" '{number: $n, labels: [$ARGS.positional[] | {name: .}]}' --args "$@"; }
{
  issue 9  type:story status:ready prio:p1
  issue 10 type:story status:ready prio:p1
  issue 11 type:bug   status:ready prio:p0
  issue 12 type:chore status:ready prio:p2
  issue 13 type:epic  status:ready prio:p0
  issue 14 type:bug   status:ready prio:p0 board
  issue 15 type:story status:backlog prio:p0
  issue 16 type:story status:ready
  issue 20 type:chore status:in-progress prio:p1
  issue 21 type:epic  status:in-progress prio:p1
  issue 22 type:story status:in-progress prio:p1 board
} | jq -s . >"$TMP/issues.json"
export GH_FIXTURE="$TMP/issues.json"
export PATH="$TMP/bin:$PATH"

export REPO=test/vigie GIT_AUTHOR_EMAIL=t@example.invalid LOG_DIR="$TMP/logs" STATE_DIR="$TMP/state"
# shellcheck source=orchestrator.sh
source "$ORCH"
set +e  # orchestrator.sh active set -e : le test gère lui-même ses échecs.

expect_eq() {
  if [ "$2" = "$3" ]; then echo "ok   $1 : $3"
  else echo "FAIL $1 : « $3 », attendu « $2 »"; failures=$((failures + 1)); fi
}

# Ordre de prise en charge : on retire chaque issue choisie et on redemande.
order=""
for _ in 1 2 3 4 5 6 7; do
  n="$(next_ready_story)"
  [ -n "$n" ] || break
  order="$order $n"
  jq --argjson n "$n" '[.[] | select(.number != $n)]' "$GH_FIXTURE" >"$TMP/next.json"
  mv "$TMP/next.json" "$GH_FIXTURE"
done
expect_eq "ordre (bug p0, stories p1 par numéro, chore p2, sans prio ; ni epic ni board)" \
  "11 9 10 12 16" "${order# }"

expect_eq "WIP : en cours de type story/chore/bug, hors epic et board" "1" "$(wip_count)"

# PR Dependabot : le steward ne repasse sur une même tête qu'une fois par jour UTC.
pr() { jq -n --argjson n "$1" --arg h "$2" '{number: $n, headRefOid: $h, labels: [$ARGS.positional[] | {name: .}]}' --args "${@:3}"; }
{ pr 22 aaa type:chore; pr 23 ccc type:chore review:approved security:approved; } | jq -s . >"$GH_FIXTURE"
triage_tick() {  # même enchaînement que tick() : choisir, marquer, (lancer le steward)
  local n head
  read -r n head <<<"$(next_dependabot_pr)" || true
  [ -z "$n" ] || mark_steward_seen "$n" "$head"
  echo "$n"
}
runs="$(triage_tick) $(triage_tick) $(triage_tick)"
expect_eq "même tête, même jour : un seul passage en trois ticks (PR approuvée ignorée)" "22" "$(echo $runs)"
{ pr 22 bbb type:chore; pr 23 ccc type:chore review:approved security:approved; } | jq -s . >"$GH_FIXTURE"
expect_eq "Dependabot met la PR à jour : nouveau passage" "22" "$(triage_tick)"
expect_eq "puis plus rien le même jour" "" "$(triage_tick)"
echo "bbb 2000-01-01" >"$STATE_DIR/steward-pr22"
expect_eq "jour suivant, même tête : revérification" "22" "$(triage_tick)"

echo
if [ "$failures" -eq 0 ]; then echo "✓ orchestrator.sh : tous les tests passent"
else echo "✗ orchestrator.sh : $failures échec(s)"; exit 1; fi
