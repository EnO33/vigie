#!/usr/bin/env bash
# Orchestrateur de la factory Vigie.
# Boucle pull : à chaque tick, la première règle applicable gagne (voir docs/factory/FACTORY.md).
# Bootstrap en bash ; candidat naturel à une réécriture en Rust par la factory elle-même.
set -euo pipefail

: "${REPO:?REPO=owner/nom requis}"
: "${GIT_AUTHOR_EMAIL:?GIT_AUTHOR_EMAIL requis : auteur des commits squash}"
WORKDIR="${WORKDIR:-/workspace/repo}"
WIP_LIMIT="${WIP_LIMIT:-1}"
TICK_SECONDS="${TICK_SECONDS:-60}"
BACKOFF_SECONDS="${BACKOFF_SECONDS:-1800}"
LOG_DIR="${LOG_DIR:-/workspace/logs}"
STATE_DIR="${STATE_DIR:-/workspace/state}"
# Notifications ntfy (facultatives) : NTFY_TOPIC vide = désactivées. Voir .env.example.
NTFY_URL="${NTFY_URL:-https://ntfy.sh}"

mkdir -p "$LOG_DIR" "$STATE_DIR"

log() { printf '%s [orchestrator] %s\n' "$(date -u +%FT%TZ)" "$*"; }

# ---------------------------------------------------------------- notifications (ntfy)

# notify <titre> <priorité> <tags> [lien] [message]   (message par défaut : le titre)
# Ne fait jamais échouer la boucle : curl -m 10, échec seulement loggé, sans l'URL (le topic vaut
# mot de passe). Le jeton passe par « -H @fichier » (substitution de processus) : il n'apparaît
# ni dans les arguments de curl, ni dans le message, ni dans les logs.
notify() {
  local title="$1" priority="$2" tags="$3" click="${4:-}" message="${5:-$1}"
  [ -n "${NTFY_TOPIC:-}" ] || return 0
  local args=(-s -m 10 -o /dev/null -w '%{http_code}'
    -H "Title: $title" -H "Priority: $priority" -H "Tags: $tags")
  [ -z "$click" ] || args+=(-H "Click: $click")
  local code="" rc=0
  if [ -n "${NTFY_TOKEN:-}" ]; then
    code="$(curl "${args[@]}" -H @<(printf 'Authorization: Bearer %s\n' "$NTFY_TOKEN") \
      --data-binary "$message" "${NTFY_URL%/}/$NTFY_TOPIC" 2>/dev/null)" || rc=$?
  else
    code="$(curl "${args[@]}" --data-binary "$message" "${NTFY_URL%/}/$NTFY_TOPIC" 2>/dev/null)" || rc=$?
  fi
  case "$rc:$code" in
    0:2??) ;;
    *) log "ntfy : notification « $title » non envoyée (curl $rc, http ${code:-?})" ;;
  esac
  return 0
}

# ---------------------------------------------------------------- agents

run_agent() {
  local agent="$1" prompt="$2"
  local out="$LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ)-$agent.json"
  log "→ $agent : $prompt"
  # Les agents n'ont pas à notifier : ni topic ni jeton ntfy dans leur environnement.
  if (cd "$WORKDIR" && env -u NTFY_TOPIC -u NTFY_TOKEN claude -p "$prompt" \
        --agent "$agent" \
        --dangerously-skip-permissions \
        --output-format json >"$out" 2>&1); then
    log "✓ $agent (log: $out)"
    return 0
  fi
  log "✗ $agent a échoué (limite d'usage probable). Pause ${BACKOFF_SECONDS}s. Log : $out"
  notify "Agent $agent en échec" high warning "" \
    "Limite d'usage probable : pause de ${BACKOFF_SECONDS}s avant le prochain tick. Log : $out"
  sleep "$BACKOFF_SECONDS"
  return 1
}

# ---------------------------------------------------------------- requêtes GitHub

# Les PR portant le label `board` appartiennent à l'humain : la factory ne les touche jamais.
NOT_BOARD='select(([.labels[].name] | index("board")) | not)'

first_pr_with() {
  gh pr list --repo "$REPO" --state open --label "$1" --json number,labels \
    --jq "[.[] | $NOT_BOARD][0].number // empty"
}

# PR en revue à qui il manque le label $1
first_in_review_missing() {
  gh pr list --repo "$REPO" --state open --label status:in-review --json number,labels \
    --jq "[.[] | $NOT_BOARD | select(([.labels[].name] | index(\"$1\")) | not)][0].number // empty"
}

first_fully_approved_pr() {
  gh pr list --repo "$REPO" --state open --json number,labels \
    --jq "[.[] | $NOT_BOARD | select(([.labels[].name] | index(\"review:approved\")) and ([.labels[].name] | index(\"security:approved\")))][0].number // empty"
}

first_untriaged_dependabot_pr() {
  gh pr list --repo "$REPO" --state open --author app/dependabot --json number,labels \
    --jq '[.[] | select(([.labels[].name] | index("review:approved")) | not)][0].number // empty'
}

# Travail pris par le développeur : stories, chores (dependency-steward, veille) et bugs
# (security-auditor). gh combine les --label en ET : le type se filtre donc en jq.
WORK_TYPES='select([.labels[].name] | any(. == "type:story" or . == "type:chore" or . == "type:bug"))'

# Travail en cours, compté contre WIP_LIMIT (hors issues du board).
wip_count() {
  gh issue list --repo "$REPO" --state open --label status:in-progress \
    --json number,labels --limit 100 \
    --jq "[.[] | $NOT_BOARD | $WORK_TYPES] | length"
}

# Issue prête (story, chore ou bug) la plus prioritaire : p0 < p1 < p2 < sans prio, puis numéro.
next_ready_story() {
  gh issue list --repo "$REPO" --state open --label status:ready \
    --json number,labels --limit 100 \
    --jq "[.[] | $NOT_BOARD | $WORK_TYPES
           | {n: .number, p: ([.labels[].name | select(startswith(\"prio:\"))][0] // \"prio:p9\")}]
          | sort_by(.p, .n) | .[0].n // empty"
}

epics_with_status() {
  gh issue list --repo "$REPO" --state open --label type:epic --label "$1" \
    --json number --jq '.[].number'
}

sub_issue_total() {
  gh api "repos/$REPO/issues/$1" --jq '.sub_issues_summary.total // 0'
}

sub_issue_completed() {
  gh api "repos/$REPO/issues/$1" --jq '.sub_issues_summary.completed // 0'
}

# Renvoie 0 si la factory doit rester en pause (issue factory:halt ouverte). Notifie une seule
# fois par transition (fichier d'état $STATE_DIR/halted). État illisible (gh en erreur) : pause
# par prudence, sans notifier ni changer l'état.
halt_gate() {
  local count marker="$STATE_DIR/halted"
  if ! count="$(gh issue list --repo "$REPO" --state open --label factory:halt \
      --json number --jq 'length' 2>/dev/null)" || ! [[ "$count" =~ ^[0-9]+$ ]]; then
    log "état factory:halt illisible : pause par prudence"
    return 0
  fi
  if [ "$count" != 0 ]; then
    if [ ! -f "$marker" ]; then
      touch "$marker"
      notify "Factory en pause" default pause_button \
        "https://github.com/$REPO/issues?q=is%3Aopen+label%3Afactory%3Ahalt" \
        "Issue factory:halt ouverte : plus aucun agent ne tourne."
    fi
    return 0
  fi
  if [ -f "$marker" ]; then
    rm -f "$marker"
    notify "Factory relancée" default arrow_forward "" "Plus d'issue factory:halt ouverte : reprise."
  fi
  return 1
}

# ---------------------------------------------------------------- étapes

merge_if_green() {
  local pr="$1" head title closes merge_out
  head="$(gh pr view "$pr" --repo "$REPO" --json headRefOid --jq .headRefOid)"
  log "gates sur PR #$pr ($head)"
  if (cd "$WORKDIR" && bash factory/gates.sh --pr "$pr") >"$LOG_DIR/gates-pr$pr.log" 2>&1; then
    # Squash au nom du board, message maîtrisé (pas de Co-authored-by généré par GitHub),
    # et uniquement si la tête de PR est celle que les gates ont validée.
    title="$(gh pr view "$pr" --repo "$REPO" --json title --jq .title)"
    closes="$(gh pr view "$pr" --repo "$REPO" --json body --jq .body | grep -oiE '^(closes|fixes) #[0-9]+' || true)"
    if merge_out="$(gh pr merge "$pr" --repo "$REPO" --squash --delete-branch \
        --match-head-commit "$head" \
        --author-email "$GIT_AUTHOR_EMAIL" \
        --subject "$title (#$pr)" \
        --body "${closes:-PR #$pr}" 2>&1)"; then
      log "✓ PR #$pr mergée"
      notify "PR #$pr mergée" default white_check_mark "https://github.com/$REPO/pull/$pr" "$title"
    else
      # Sans approbations ni status:in-review, aucune règle du tick ne reprend la PR : pas de
      # boucle reviewer → gates → refus. status:blocked la laisse au board.
      log "✗ merge de la PR #$pr refusé par GitHub : PR bloquée"
      gh pr comment "$pr" --repo "$REPO" --body "merge refusé par GitHub malgré des gates verts. PR bloquée pour le board. sortie de gh pr merge :
\`\`\`
$(printf '%s\n' "$merge_out" | tail -n 30 | sed -E 's/(gh[pousr]_|github_pat_)[A-Za-z0-9_]+/[jeton masqué]/g')
\`\`\`"
      gh pr edit "$pr" --repo "$REPO" \
        --remove-label review:approved --remove-label security:approved --remove-label status:in-review \
        --add-label status:blocked
      notify "Merge refusé : PR #$pr" high warning "https://github.com/$REPO/pull/$pr" "$title"
    fi
  else
    gh pr comment "$pr" --repo "$REPO" --body "gates rouges. extrait :
\`\`\`
$(tail -n 60 "$LOG_DIR/gates-pr$pr.log")
\`\`\`"
    gh pr edit "$pr" --repo "$REPO" \
      --remove-label review:approved --remove-label security:approved --remove-label status:in-review \
      --add-label status:changes-requested
    log "✗ PR #$pr renvoyée en changes-requested"
    notify "Gates rouges : PR #$pr" high x "https://github.com/$REPO/pull/$pr" \
      "PR renvoyée en changes-requested."
  fi
}

notify_weekly_report() {
  local url
  url="$(gh issue list --repo "$REPO" --state all --label type:report --limit 1 \
    --json url --jq '.[0].url // empty' 2>/dev/null || true)"
  notify "Rapport hebdomadaire publié" low memo "$url" "Rapport du product-owner au board."
}

# Signe de vie (priorité min), au premier passage de chaque jour UTC.
heartbeat() {
  local stamp="$STATE_DIR/last-heartbeat" today since merged open state="active"
  today="$(date -u +%F)"
  [ "$(cat "$stamp" 2>/dev/null)" != "$today" ] || return 0
  echo "$today" >"$stamp"
  since="$(date -u -d '24 hours ago' +%FT%TZ)"
  merged="$(gh pr list --repo "$REPO" --state merged --search "merged:>=$since" --limit 100 \
    --json number --jq 'length' 2>/dev/null || echo '?')"
  open="$(gh pr list --repo "$REPO" --state open --limit 100 --json number --jq 'length' 2>/dev/null || echo '?')"
  [ ! -f "$STATE_DIR/halted" ] || state="en pause"
  notify "Vigie : signe de vie" min heartpulse "https://github.com/$REPO/pulls" \
    "Factory $state. Merges (24 h) : $merged. PR ouvertes : $open."
}

close_finished_epics() {
  local epic total completed
  for epic in $(epics_with_status status:in-progress); do
    total="$(sub_issue_total "$epic")"
    completed="$(sub_issue_completed "$epic")"
    if [ "$total" -gt 0 ] && [ "$total" = "$completed" ]; then
      gh issue close "$epic" --repo "$REPO" --comment "toutes les sub-issues closes ($completed/$total)."
      log "✓ epic #$epic clos"
    fi
  done
}

weekly_due() {
  local stamp="$STATE_DIR/last-weekly"
  [ ! -f "$stamp" ] || [ -n "$(find "$stamp" -mtime +6)" ]
}

sync_main() {
  (cd "$WORKDIR" && git fetch --prune origin && git checkout --quiet main && git reset --quiet --hard origin/main)
}

# ---------------------------------------------------------------- tick

tick() {
  local n
  sync_main
  close_finished_epics

  if weekly_due; then
    run_agent tech-watch "Mission hebdomadaire de veille." &&
      run_agent product-owner "Mission rapport hebdomadaire au board." &&
      touch "$STATE_DIR/last-weekly" &&
      notify_weekly_report
    return
  fi

  n="$(first_pr_with status:changes-requested)"
  if [ -n "$n" ]; then run_agent developer "Mission : corriger la PR #$n."; return; fi

  n="$(first_in_review_missing review:approved)"
  if [ -n "$n" ]; then run_agent reviewer "Mission : revoir la PR #$n."; return; fi

  n="$(first_in_review_missing security:approved)"
  if [ -n "$n" ]; then run_agent security-auditor "Mission : auditer la PR #$n."; return; fi

  n="$(first_fully_approved_pr)"
  if [ -n "$n" ]; then merge_if_green "$n"; return; fi

  n="$(first_untriaged_dependabot_pr)"
  if [ -n "$n" ]; then run_agent dependency-steward "Mission : traiter la PR Dependabot #$n."; return; fi

  if [ "$(wip_count)" -lt "$WIP_LIMIT" ]; then
    n="$(next_ready_story)"
    if [ -n "$n" ]; then run_agent developer "Mission : implémenter l'issue #$n."; return; fi
  fi

  for n in $(epics_with_status status:ready); do
    if [ "$(sub_issue_total "$n")" = "0" ]; then
      run_agent architect "Mission : découper l'epic #$n."; return
    fi
  done

  n="$(gh issue list --repo "$REPO" --state open --label status:blocked --json number --jq '.[0].number // empty')"
  if [ -n "$n" ]; then run_agent architect "Mission : débloquer l'issue #$n."; return; fi

  if [ -z "$(epics_with_status status:ready)" ] && [ -z "$(epics_with_status status:in-progress)" ]; then
    run_agent product-owner "Mission : planifier le prochain epic."; return
  fi

  log "rien à faire"
}

main() {
  log "démarrage (repo=$REPO, wip=$WIP_LIMIT)"
  # Premier signe de vie le lendemain du premier démarrage, pas en même temps que celui-ci.
  [ -f "$STATE_DIR/last-heartbeat" ] || date -u +%F >"$STATE_DIR/last-heartbeat"
  notify "Factory démarrée" default rocket "https://github.com/$REPO" "Dépôt $REPO, WIP $WIP_LIMIT."
  while true; do
    heartbeat
    if halt_gate; then
      log "issue factory:halt ouverte : pause"
    else
      tick || log "tick en erreur, on continue au prochain"
    fi
    sleep "$TICK_SECONDS"
  done
}

# Sourcé (factory/orchestrator.test.sh) : définit les fonctions sans lancer la boucle.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
