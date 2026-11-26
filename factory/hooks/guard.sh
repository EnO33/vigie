#!/usr/bin/env bash
# Hook PreToolUse (agents de la factory uniquement, FACTORY_AGENT=1).
# Exit 2 = action refusée, le message stderr est renvoyé à l'agent.
#
# Défense en profondeur, pas une frontière de sécurité : ce hook reconnaît les formes usuelles
# des commandes interdites (gh, curl, wget). Il ne voit ni un script python ou node, ni une
# commande encodée ou reconstruite à l'exécution, et ne cherche pas à les voir. Les vraies
# barrières sont ailleurs : ruleset de main, gates objectifs, droits limités du token.
# Tests : bash factory/hooks/guard.test.sh (lancés par l'étape « hooks » de factory/gates.sh).
set -euo pipefail
[ "${FACTORY_AGENT:-0}" = "1" ] || exit 0

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROTECTED_RE='^(VISION\.md|CLAUDE\.md|docs/(factory|engineering)/|clippy\.toml|deny\.toml|rustfmt\.toml|rust-toolchain\.toml|\.claude/|\.zed/|\.githooks/|\.github/|docker/|docker-compose\.yml|factory/|xtask/|\.cargo/)'
input="$(cat)"
tool="$(jq -r '.tool_name' <<<"$input")"

deny() { echo "refusé par la factory : $1" >&2; exit 2; }

# Forme unique d'un chemin : C:\…, C:/… et /c/… (Windows) comme Linux.
canon() {
  local p="${1//\\//}"
  if command -v cygpath >/dev/null 2>&1; then p="$(cygpath -u "$p")"; fi
  realpath -m "$p"
}

# Chemin relatif à la racine du dépôt ; un worktree d'agent (../wt/<n>/) compte comme le dépôt.
relative_to_repo() {
  local rel
  rel="$(realpath -m --relative-to="$(canon "$ROOT")" "$(canon "$1")")"
  sed -E 's#^(\.\./)*wt/[^/]+/##' <<<"$rel"
}

no_attribution() {
  if grep -qiE -f "$ROOT/factory/attribution.patterns" <<<"$1"; then
    deny "attribution IA interdite (commit, PR, issue) : seul le compte du board apparaît"
  fi
}

case "$tool" in
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
    grep -qE 'push[^|;&]*(--force|-f( |$))' <<<"$cmd" && deny "pas de force-push"
    grep -qE -- '--no-verify' <<<"$cmd" && deny "pas de --no-verify"
    grep -qE 'core\.hooksPath' <<<"$cmd" && deny "les hooks Git du dépôt ne se désactivent pas"
    grep -qE 'gh pr merge' <<<"$cmd" && deny "seul l'orchestrateur merge"
    grep -qE 'gh pr review[^|;&]*--approve' <<<"$cmd" && deny "approbation via labels uniquement"
    grep -qE 'gh (pr|issue) edit[^|;&]*--add-label[^|;&]*\bboard\b' <<<"$cmd" && deny "le label board est réservé au board"
    # Endpoints du board et de l'orchestrateur : merge, statut des gates, règles du dépôt.
    grep -qE 'gh[[:space:]]+api[^|;&]*/(merges?|statuses|rulesets|interaction-limits|branches/[^[:space:]]+/protection)([/?"'\''[:space:]]|$)' <<<"$cmd" \
      && deny "endpoint réservé au board et à l'orchestrateur (merge, statuts, règles du dépôt)"
    grep -qE '(^|[[:space:]])--admin([[:space:]=]|$)' <<<"$cmd" && deny "pas de --admin : aucun contournement des règles de branche"
    # Mêmes opérations en GraphQL : merge, auto-merge, rulesets, protection de branche.
    if grep -qE 'graphql' <<<"$cmd" \
      && grep -qE '\b(mergePullRequest|mergeBranch|enablePullRequest(Auto|Agent)Merge|(create|update|delete)(RepositoryRuleset|BranchProtectionRule))\b' <<<"$cmd"; then
      deny "mutation GraphQL réservée au board et à l'orchestrateur (merge, rulesets, protection)"
    fi
    # Appels directs à l'API GitHub : passer par gh, que ce hook sait lire.
    grep -qE '\b(curl|wget)\b[^|;&]*api\.github\.com' <<<"$cmd" && deny "pas de curl/wget vers api.github.com : utilise gh"
    no_attribution "$cmd"
    ;;
  Edit|Write|MultiEdit|NotebookEdit)
    path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
    rel="$(relative_to_repo "$path")"
    grep -qE "$PROTECTED_RE" <<<"$rel" \
      && deny "$rel est protégé (board uniquement). Ouvre une issue area:factory."
    ;;
esac
exit 0
