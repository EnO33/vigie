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

mkdir -p "$LOG_DIR" "$STATE_DIR"

log() { printf '%s [orchestrator] %s\n' "$(date -u +%FT%TZ)" "$*"; }

# ---------------------------------------------------------------- agents

run_agent() {
  local agent="$1" prompt="$2"
  local out="$LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ)-$agent.json"
  log "→ $agent : $prompt"
  if (cd "$WORKDIR" && claude -p "$prompt" \
        --agent "$agent" \
        --dangerously-skip-permissions \
        --output-format json >"$out" 2>&1); then
    log "✓ $agent (log: $out)"
    return 0
  fi
  log "✗ $agent a échoué (limite d'usage probable). Pause ${BACKOFF_SECONDS}s. Log : $out"
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

count_issues() {
  gh issue list --repo "$REPO" --state open --label "$1" --label "$2" --json number --jq 'length'
}

# story prête la plus prioritaire (p0 < p1 < p2)
next_ready_story() {
  gh issue list --repo "$REPO" --state open --label type:story --label status:ready \
    --json number,labels --limit 100 \
    --jq '[.[] | {n: .number, p: ([.labels[].name | select(startswith("prio:"))][0] // "prio:p9")}]
          | sort_by(.p, .n) | .[0].n // empty'
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

halt_requested() {
  [ "$(gh issue list --repo "$REPO" --state open --label factory:halt --json number --jq 'length')" != "0" ]
}

# ---------------------------------------------------------------- étapes

merge_if_green() {
  local pr="$1" head title closes
  head="$(gh pr view "$pr" --repo "$REPO" --json headRefOid --jq .headRefOid)"
  log "gates sur PR #$pr ($head)"
  if (cd "$WORKDIR" && bash factory/gates.sh --pr "$pr") >"$LOG_DIR/gates-pr$pr.log" 2>&1; then
    # Squash au nom du board, message maîtrisé (pas de Co-authored-by généré par GitHub),
    # et uniquement si la tête de PR est celle que les gates ont validée.
    title="$(gh pr view "$pr" --repo "$REPO" --json title --jq .title)"
    closes="$(gh pr view "$pr" --repo "$REPO" --json body --jq .body | grep -oiE '^(closes|fixes) #[0-9]+' || true)"
    gh pr merge "$pr" --repo "$REPO" --squash --delete-branch \
      --match-head-commit "$head" \
      --author-email "$GIT_AUTHOR_EMAIL" \
      --subject "$title (#$pr)" \
      --body "${closes:-PR #$pr}"
    log "✓ PR #$pr mergée"
  else
    gh pr comment "$pr" --repo "$REPO" --body "gates rouges. extrait :
\`\`\`
$(tail -n 60 "$LOG_DIR/gates-pr$pr.log")
\`\`\`"
    gh pr edit "$pr" --repo "$REPO" \
      --remove-label review:approved --remove-label security:approved --remove-label status:in-review \
      --add-label status:changes-requested
    log "✗ PR #$pr renvoyée en changes-requested"
  fi
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
      touch "$STATE_DIR/last-weekly"
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

  if [ "$(count_issues type:story status:in-progress)" -lt "$WIP_LIMIT" ]; then
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
  while true; do
    if halt_requested; then
      log "issue factory:halt ouverte : pause"
    else
      tick || log "tick en erreur, on continue au prochain"
    fi
    sleep "$TICK_SECONDS"
  done
}

main "$@"
