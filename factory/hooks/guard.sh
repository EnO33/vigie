#!/usr/bin/env bash
# Hook PreToolUse (agents de la factory uniquement, FACTORY_AGENT=1).
# Exit 2 = action refusée, le message stderr est renvoyé à l'agent.
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
