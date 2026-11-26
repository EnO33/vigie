#!/usr/bin/env bash
# Tests du chemin « gates.sh --pr » : une étape rouge doit publier le status failure.
#   bash factory/gates.test.sh
# Environnement jetable : un origin nu (main = HEAD courant, refs/pull/7/head = main + un commit
# propre), un cargo factice qui échoue sur l'étape demandée et un gh factice qui consigne les
# statuts publiés au lieu d'appeler GitHub.
set -uo pipefail

GATES="$(cd "$(dirname "$0")" && pwd)/gates.sh"
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

mkdir -p "$TMP/bin"
cat >"$TMP/bin/cargo" <<'EOF'
#!/usr/bin/env bash
# cargo factice : note l'étape, échoue si c'est FAIL_STEP.
echo "$1" >>"$GATES_TEST_DIR/calls"
[ "$1" = "${FAIL_STEP:-}" ] && { echo "cargo factice : échec de $1" >&2; exit 1; }
exit 0
EOF
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
# gh factice : titre et corps de PR fixes ; « gh api …/statuses/… -f state=X » consigne X.
case "$1 $2" in
  "pr view") printf 'docs: test\nCorps de la PR de test.\n' ;;
  api\ *)
    for arg in "$@"; do
      case "$arg" in state=*) echo "${arg#state=}" >>"$GATES_TEST_DIR/statuses" ;; esac
    done ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/cargo" "$TMP/bin/gh"

git init -q --bare --initial-branch=main "$TMP/origin.git"
git -C "$REPO_ROOT" push -q "$TMP/origin.git" HEAD:refs/heads/main
git clone -q "$TMP/origin.git" "$TMP/wd"
git -C "$TMP/wd" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m "docs: test"
git -C "$TMP/wd" push -q origin HEAD:refs/pull/7/head
# PR 8 : remplace gates.sh par un script qui valide tout.
printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/wd/factory/gates.sh"
git -C "$TMP/wd" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@example.invalid \
  commit -q -am "chore: gates complaisants"
git -C "$TMP/wd" push -q origin HEAD:refs/pull/8/head

# Lance « gates.sh --pr <N> » (7 par défaut) ; FAIL_STEP vide = aucun échec.
run_pr() {
  : >"$TMP/calls"; : >"$TMP/statuses"
  (cd "$TMP/wd" && PATH="$TMP/bin:$PATH" GATES_TEST_DIR="$TMP" FAIL_STEP="$1" \
    bash "$GATES" --pr "${2:-7}" >"$TMP/out" 2>&1)
}

last_status() { tail -n 1 "$TMP/statuses"; }

check() {
  local label="$1" want="$2" got; got="$(last_status)"
  if [ "$got" = "$want" ]; then echo "ok   $label : status $got"
  else
    echo "FAIL $label : status « $got », attendu « $want »"; failures=$((failures + 1))
    sed 's/^/     | /' "$TMP/out" | tail -n 15
  fi
}

run_pr ""
check "aucune étape rouge" success

for step in fmt clippy test xtask deny llvm-cov; do
  run_pr "$step"
  check "étape cargo $step rouge" failure
  # set -e doit arrêter les contrôles à l'étape rouge : la suivante ne tourne pas.
  next="$(grep -A1 -x "$step" "$TMP/calls" | sed -n 2p)"
  if [ -n "$next" ]; then
    echo "FAIL étape cargo $step rouge : « $next » a tourné après l'échec"; failures=$((failures + 1))
  fi
done

# Les contrôles viennent du gates.sh de confiance, pas de la copie de la PR.
run_pr "" 8
check "PR qui remplace gates.sh par « exit 0 »" failure

echo
if [ "$failures" -eq 0 ]; then echo "✓ gates.sh --pr : tous les tests passent"
else echo "✗ gates.sh --pr : $failures échec(s)"; exit 1; fi
