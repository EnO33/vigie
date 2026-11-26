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
# cargo factice : note l'étape, échoue si c'est FAIL_STEP. À l'étape test, échoue aussi si
# REQUIRE_FILE manque, ou si tous les fichiers de BREAK_IF_ALL sont présents ensemble.
echo "$1" >>"$GATES_TEST_DIR/calls"
[ "$1" = "${FAIL_STEP:-}" ] && { echo "cargo factice : échec de $1" >&2; exit 1; }
if [ "$1" = test ]; then
  if [ -n "${REQUIRE_FILE:-}" ] && [ ! -f "$REQUIRE_FILE" ]; then
    echo "cargo factice : $REQUIRE_FILE absent" >&2; exit 1
  fi
  if [ -n "${BREAK_IF_ALL:-}" ]; then
    all=1; for f in $BREAK_IF_ALL; do [ -f "$f" ] || all=0; done
    [ "$all" = 0 ] || { echo "cargo factice : combinaison cassée" >&2; exit 1; }
  fi
fi
exit 0
EOF
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
# gh factice : titre et corps de PR fixes ; « gh api …/statuses/… -f state=X » consigne X.
case "$1 $2" in
  "pr view") printf 'docs: test\nCorps de la PR de test.\n' ;;
  api\ *)
    for arg in "$@"; do
      case "$arg" in
        */statuses/*) echo "${arg##*/}" >>"$GATES_TEST_DIR/status-shas" ;;
        state=*) echo "${arg#state=}" >>"$GATES_TEST_DIR/statuses" ;;
      esac
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

# PR en retard sur main, toutes parties d'une base B plus ancienne. main avance ensuite :
# C restaure un test de l'outillage absent de B, D modifie la 1re ligne du README, E ajoute
# marqueur-main. Aucune PR ne touche un fichier protégé.
g() { git -C "$TMP/wd" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@example.invalid "$@"; }
g checkout -q -B base origin/main
g rm -q factory/orchestrator-notify.test.sh
g commit -q -m "chore: base sans le test ntfy"
B="$(git -C "$TMP/wd" rev-parse HEAD)"
# PR 9 : en retard, sans conflit.
g checkout -q -B pr9 "$B"
g commit -q --allow-empty -m "docs: PR partie de l'ancienne base"
g push -q origin pr9:refs/pull/9/head
# PR 11 : modifie la même ligne du README que D (conflit).
g checkout -q -B pr11 "$B"
sed -i '1s/.*/# Vigie (PR)/' "$TMP/wd/README.md"
g commit -q -am "docs: titre du README côté PR"
g push -q origin pr11:refs/pull/11/head
# PR 12 : ajoute marqueur-pr, qui ne casse qu'avec marqueur-main (E).
g checkout -q -B pr12 "$B"
echo pr >"$TMP/wd/marqueur-pr"; g add marqueur-pr
g commit -q -m "feat: marqueur côté PR"
g push -q origin pr12:refs/pull/12/head
# main : C, D, E.
g checkout -q base
g checkout -q origin/main -- factory/orchestrator-notify.test.sh
g commit -q -m "chore: main reçoit le test ntfy"
sed -i '1s/.*/# Vigie (main)/' "$TMP/wd/README.md"
g commit -q -am "docs: titre du README côté main"
echo main >"$TMP/wd/marqueur-main"; g add marqueur-main
g commit -q -m "feat: marqueur côté main"
g push -q origin base:refs/heads/main

# Lance « gates.sh --pr <N> » (7 par défaut) ; FAIL_STEP vide = aucun échec.
run_pr() {
  : >"$TMP/calls"; : >"$TMP/statuses"; : >"$TMP/status-shas"
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

# PR en retard sans conflit : tests de l'outillage pris sur main, gates jugés sur la fusion
# (le cargo factice exige marqueur-main, qui n'existe que sur main).
export REQUIRE_FILE=marqueur-main
run_pr "" 9
check "PR en retard sans conflit : gates sur la fusion avec main" success
unset REQUIRE_FILE
head9="$(git -C "$TMP/wd" rev-parse refs/heads/pr9)"
if [ "$(sort -u "$TMP/status-shas")" = "$head9" ]; then echo "ok   status publié sur la tête de la PR, pas sur la fusion"
else echo "FAIL status publié sur « $(sort -u "$TMP/status-shas" | paste -sd' ' -) », attendu $head9"; failures=$((failures + 1)); fi

# PR en conflit avec main : failure, message explicite, aucune étape cargo.
run_pr "" 11
check "PR en conflit avec main" failure
if grep -q "branche en conflit avec main : à mettre à jour" "$TMP/out"; then echo "ok   PR en conflit : message explicite"
else echo "FAIL PR en conflit : message absent"; failures=$((failures + 1)); fi
if [ -s "$TMP/calls" ]; then echo "FAIL PR en conflit : cargo a tourné"; failures=$((failures + 1))
else echo "ok   PR en conflit : aucune étape cargo"; fi

# PR en retard qui ne casse qu'une fois fusionnée avec main.
export BREAK_IF_ALL="marqueur-main marqueur-pr"
run_pr "" 12
check "PR en retard qui casse une fois fusionnée" failure
unset BREAK_IF_ALL

# Les contrôles viennent du gates.sh de confiance, pas de la copie de la PR.
run_pr "" 8
check "PR qui remplace gates.sh par « exit 0 »" failure

echo
if [ "$failures" -eq 0 ]; then echo "✓ gates.sh --pr : tous les tests passent"
else echo "✗ gates.sh --pr : $failures échec(s)"; exit 1; fi
