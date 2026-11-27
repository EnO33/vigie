#!/usr/bin/env bash
# Tests du garde-fou « passage sans effet » de factory/orchestrator.sh.
#   bash factory/orchestrator-stall.test.sh
# Un passage d'agent qui ne change ni l'état, ni les labels, ni la tête de PR de sa cible met
# celle-ci de côté STALL_HOURS heures : la sélection passe au candidat suivant au lieu de boucler.
# gh factice : issues en JSON dans $FAKE/issues/<n>.json ; claude factice : effet choisi par test.
set -uo pipefail

ORCH="$(cd "$(dirname "$0")" && pwd)/orchestrator.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FAKE="$TMP/fake"
mkdir -p "$TMP/bin" "$FAKE/issues"
failures=0

cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
arg_after() { local prev="" a; for a in "${@:2}"; do [ "$prev" = "$1" ] && printf '%s' "$a"; prev="$a"; done; }
expr="$(arg_after --jq "$@")"; expr="${expr:-.}"
all() { cat "$FAKE"/issues/*.json 2>/dev/null | jq -s .; }
path=""; for a in "$@"; do case "$a" in repos/*) path="${a%%\?*}"; break ;; esac; done
case "$1 $2" in
  "api graphql") cat "$FAKE/closed-count" ;;  # nombre d'issues fermées (--jq du vrai gh appliqué)
  "api "*)
    case "$path" in
      */timeline) n="${path%/timeline}"; jq -r "$expr" "$FAKE/timeline-${n##*/}.json" 2>/dev/null ;;
      */issues/*) jq -r "$expr" "$FAKE/issues/${path##*/}.json" ;;
      */pulls/*)  jq -r "$expr" "$FAKE/issues/${path##*/}.json" ;;
    esac ;;
  "pr edit")
    f="$FAKE/issues/$3.json"; prev=""
    for a in "$@"; do
      case "$prev" in
        --remove-label) jq --arg l "$a" '.labels |= map(select(.name != $l))' "$f" >"$f.tmp" && mv "$f.tmp" "$f" ;;
        --add-label) jq --arg l "$a" '.labels += [{name: $l}]' "$f" >"$f.tmp" && mv "$f.tmp" "$f" ;;
      esac
      prev="$a"
    done ;;
  "pr comment") arg_after --body "$@" >"$FAKE/comment-$3" ;;
  "issue list"|"pr list")
    if [ "$1" = pr ]; then kind='select(.pull_request != null)'; else kind='select(.pull_request == null)'; fi
    data="$(all | jq "[.[] | $kind]")"
    [ "$(arg_after --state "$@")" = all ] || data="$(jq '[.[] | select(.state == "open")]' <<<"$data")"
    [ -z "$(arg_after --author "$@")" ] || data='[]'
    prev=""
    for a in "$@"; do
      [ "$prev" = --label ] && data="$(jq --arg l "$a" '[.[] | select([.labels[].name] | index($l))]' <<<"$data")"
      prev="$a"
    done
    jq -r "$expr" <<<"$data" ;;
esac
EOF
# claude factice : note « <agent> <cible> » ; effet « touch » = ajoute un label à la cible.
cat >"$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
prompt="" agent=""
while [ $# -gt 0 ]; do case "$1" in -p) prompt="$2"; shift 2 ;; --agent) agent="$2"; shift 2 ;; *) shift ;; esac; done
target="$(grep -oE '#[0-9]+' <<<"$prompt" | head -n 1 | tr -d '#')"
echo "$agent ${target:-plan}" >>"$FAKE/runs"
if [ "$(cat "$FAKE/effect" 2>/dev/null)" = touch ]; then
  if [ -n "$target" ]; then
    f="$FAKE/issues/$target.json"; jq '.labels += [{name: "touched"}]' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  else
    jq -n '{number: 99, state: "open", pull_request: null, labels: [{name: "type:epic"}, {name: "status:backlog"}], sub_issues_summary: {total: 0}}' >"$FAKE/issues/99.json"
  fi
fi
exit "${FAKE_CLAUDE_RC:-0}"
EOF
chmod +x "$TMP/bin/gh" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

issue() {  # issue <n> <labels…>
  local n="$1"; shift
  jq -n --argjson n "$n" '{number: $n, state: "open", pull_request: null, sub_issues_summary: {total: 0},
    labels: [$ARGS.positional[] | {name: .}]}' --args "$@" >"$FAKE/issues/$n.json"
}
issue 23 type:chore status:ready prio:p1
issue 30 type:story status:ready prio:p2

export REPO=test/vigie GIT_AUTHOR_EMAIL=t@example.invalid LOG_DIR="$TMP/logs" STATE_DIR="$TMP/state" \
  WORKDIR="$TMP" BACKOFF_SECONDS=0 NTFY_TOPIC=""
# shellcheck source=orchestrator.sh
source "$ORCH"
set +e
# Hors sujet ici : synchro Git, epics finis, missions hebdomadaires ; notify consigné.
sync_main() { :; }
close_finished_epics() { :; }
weekly_due() { return 1; }
notify() { echo "$1 | ${5:-}" >>"$FAKE/notifs"; }  # titre | message

expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 : « $3 », attendu « $2 »"; failures=$((failures + 1)); fi; }
runs() { paste -sd, "$FAKE/runs" 2>/dev/null; }
notifs() { grep -c . "$FAKE/notifs" 2>/dev/null || echo 0; }
reset_runs() { rm -f "$FAKE/runs" "$FAKE/notifs"; }

# --- passages sans effet : chaque cible passe une fois, puis la sélection passe à la suivante
echo none >"$FAKE/effect"
for _ in 1 2 3 4; do tick >/dev/null 2>&1; done
expect "4 ticks sans effet : #23, puis #30, puis la planification, puis plus rien" \
  "developer 23,developer 30,product-owner plan" "$(runs)"
expect "une notification « sans effet » par cible mise de côté" 3 "$(grep -c 'sans effet' "$FAKE/notifs")"
grep -q "^La factory est inactive" "$FAKE/notifs" && echo "ok   4e tick sans travail : notification « inactive »" \n  || { echo "FAIL 4e tick sans travail : pas de notification « inactive »"; failures=$((failures + 1)); }
grep -q "Agent developer sans effet sur #23" "$FAKE/notifs" && echo "ok   notification nommant l'agent et la cible" \
  || { echo "FAIL notification sans agent ni cible"; failures=$((failures + 1)); }

# --- la cible change d'état (le board la relabellise) : reprise
reset_runs
issue 23 type:chore status:ready prio:p1 area:factory
tick >/dev/null 2>&1
expect "état changé hors agent : #23 repris" "developer 23" "$(runs)"

# --- 24 h écoulées : reprise
reset_runs
read -r _ fp <"$STATE_DIR/stalled-30"
echo "$(( $(date -u +%s) - 25 * 3600 )) $fp" >"$STATE_DIR/stalled-30"
tick >/dev/null 2>&1
expect "mise de côté expirée : #30 repris" "developer 30" "$(runs)"

# --- passage avec effet : pas de mise de côté, pas de notification
reset_runs; rm -f "$STATE_DIR"/stalled-*
echo touch >"$FAKE/effect"
tick >/dev/null 2>&1
expect "passage avec effet : agent lancé" "developer 23" "$(runs)"
[ ! -f "$STATE_DIR/stalled-23" ] && echo "ok   passage avec effet : pas de mise de côté" \
  || { echo "FAIL passage avec effet mis de côté"; failures=$((failures + 1)); }
expect "passage avec effet : aucune notification « sans effet »" 0 "$(notifs)"

# --- agent en échec (limite d'usage) : pas de mise de côté
reset_runs; rm -f "$STATE_DIR"/stalled-*
echo none >"$FAKE/effect"
FAKE_CLAUDE_RC=1 tick >/dev/null 2>&1
[ ! -f "$STATE_DIR/stalled-23" ] && echo "ok   agent en échec : pas de mise de côté" \
  || { echo "FAIL agent en échec mis de côté"; failures=$((failures + 1)); }

# --- revue sans fin : au 4e passage en status:changes-requested, la PR est bloquée
reset_runs; rm -f "$FAKE"/issues/*.json "$STATE_DIR"/stalled-*
jq -n '{number: 40, state: "open", pull_request: {}, sub_issues_summary: {total: 0},
  labels: [{name: "status:changes-requested"}]}' >"$FAKE/issues/40.json"
timeline() {  # timeline <n> : n passages en status:changes-requested, plus un autre label
  jq -n --argjson n "$1" '[range($n) | {event: "labeled", label: {name: "status:changes-requested"}}]
    + [{event: "labeled", label: {name: "status:in-review"}}, {event: "commented"}]' >"$FAKE/timeline-40.json"
}
timeline 3
tick >/dev/null 2>&1
expect "3 passages : le développeur corrige la PR" "developer 40" "$(runs)"
reset_runs; rm -f "$STATE_DIR"/stalled-*
timeline 4
tick >/dev/null 2>&1
expect "4e passage : plus de développeur" "" "$(runs)"
expect "4e passage : PR en status:blocked, sans status:changes-requested" "status:blocked" \
  "$(jq -r '[.labels[].name] | join(",")' "$FAKE/issues/40.json")"
grep -q "PR #40 : 4 tours de revue sans accord" "$FAKE/notifs" 2>/dev/null \
  && echo "ok   4e passage : notification « PR #40 : 4 tours de revue sans accord »" \
  || { echo "FAIL 4e passage : notification absente"; failures=$((failures + 1)); }
[ -s "$FAKE/comment-40" ] && echo "ok   4e passage : commentaire sur la PR" \
  || { echo "FAIL 4e passage : pas de commentaire"; failures=$((failures + 1)); }
reset_runs
tick >/dev/null 2>&1
case "$(runs)" in *"developer 40"*) echo "FAIL PR bloquée reprise au tick suivant"; failures=$((failures + 1)) ;;
  *) echo "ok   PR bloquée : pas reprise au tick suivant" ;; esac

# --- réveil : une issue fermée (merge ou à la main) lève les mises de côté, sauf « plan »
stall_now() { local k; for k in "$@"; do echo "$(date -u +%s) x" >"$STATE_DIR/stalled-$k"; done; }
stalled_keys() { ls "$STATE_DIR" | sed -n 's/^stalled-//p' | sort | paste -sd' ' -; }
rm -f "$STATE_DIR"/stalled-* "$STATE_DIR/closed-issues"
stall_now 19 20 plan
echo 12 >"$FAKE/closed-count"; wake_on_closed_issues
expect "premier relevé : rien d'effacé" "19 20 plan" "$(stalled_keys)"
wake_on_closed_issues
expect "même nombre d'issues fermées : rien d'effacé" "19 20 plan" "$(stalled_keys)"
echo 13 >"$FAKE/closed-count"; wake_on_closed_issues
expect "une issue fermée de plus : mises de côté levées, sauf « plan »" "plan" "$(stalled_keys)"
echo erreur >"$FAKE/closed-count"; stall_now 19; wake_on_closed_issues
expect "relevé illisible : rien d'effacé" "19 plan" "$(stalled_keys)"

# --- factory inactive : une notification par changement de la liste des mises de côté
rm -f "$FAKE/notifs" "$STATE_DIR"/stalled-* "$STATE_DIR/idle-list"
stall_now 20 19
notify_idle; notify_idle
expect "inactive : une seule notification pour la même liste" 1 "$(notifs)"
grep -qE "^La factory est inactive : #19, #20 mises de côté jusqu'à (demain )?[0-9]{2}:[0-9]{2} UTC" "$FAKE/notifs" \
  && echo "ok   inactive : « #19, #20 mises de côté jusqu'à HH:MM UTC »" \
  || { echo "FAIL inactive : titre « $(head -n 1 "$FAKE/notifs") »"; failures=$((failures + 1)); }
stall_now 23; notify_idle
expect "inactive : nouvelle notification quand la liste change" 2 "$(notifs)"
for k in 19 20 23; do echo "$(( $(date -u +%s) - 25 * 3600 )) x" >"$STATE_DIR/stalled-$k"; done
notify_idle
expect "inactive : mises de côté expirées, liste vide, aucune notification" 2 "$(notifs)"
rm -f "$FAKE/notifs" "$STATE_DIR/last-heartbeat"; stall_now 19
heartbeat
grep -qE "Inactive : #19 mise de côté jusqu'à (demain )?[0-9]{2}:[0-9]{2} UTC" "$FAKE/notifs" \
  && echo "ok   signe de vie : mises de côté" \
  || { echo "FAIL signe de vie : « $(cat "$FAKE/notifs") »"; failures=$((failures + 1)); }

echo
if [ "$failures" -eq 0 ]; then echo "✓ garde-fou sans effet : tous les tests passent"
else echo "✗ garde-fou sans effet : $failures échec(s)"; exit 1; fi
