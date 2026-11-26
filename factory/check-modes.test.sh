#!/usr/bin/env bash
# Tests de factory/check-modes.sh, sur des dépôts Git jetables.
#   bash factory/check-modes.test.sh
set -uo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/check-modes.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

# Nouveau dépôt vide, avec core.fileMode=false comme sous Windows.
new_repo() {
  rm -rf "$TMP/r"
  git init -q "$TMP/r"
  git -C "$TMP/r" config core.fileMode false
  git -C "$TMP/r" config core.autocrlf false
}

# Ajoute un fichier à l'index avec le mode demandé : +x (100755) ou -x (100644).
add_file() {
  mkdir -p "$TMP/r/$(dirname "$1")"
  echo 'echo x' >"$TMP/r/$1"
  git -C "$TMP/r" add -- "$1"
  git -C "$TMP/r" update-index --chmod="$2" -- "$1"
}

expect() {
  local want="$1" label="$2" rc=0
  (cd "$TMP/r" && bash "$CHECK" >/dev/null 2>&1) || rc=$?
  if [ "$rc" = "$want" ]; then echo "ok   $label"
  else echo "FAIL $label (code $rc, attendu $want)"; failures=$((failures + 1)); fi
}

new_repo
expect 0 "dépôt sans script : accepté"

new_repo; add_file run.sh +x; add_file factory/bin/x.sh +x; add_file .githooks/commit-msg +x
expect 0 "scripts et hooks en 100755 : acceptés"

new_repo; add_file run.sh -x
expect 1 "script à la racine en 100644 : refusé"

new_repo; add_file factory/bin/x.sh +x; add_file factory/hooks/y.sh -x
expect 1 "script en sous-dossier en 100644 : refusé"

new_repo; add_file .githooks/commit-msg -x
expect 1 "hook Git sans extension en 100644 : refusé"

new_repo; add_file run.sh +x; add_file README.md -x; add_file factory/plugins.lock -x
expect 0 "fichiers non scripts en 100644 : ignorés"

echo
if [ "$failures" -eq 0 ]; then echo "✓ check-modes.sh : tous les tests passent"
else echo "✗ check-modes.sh : $failures échec(s)"; exit 1; fi
