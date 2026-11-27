#!/usr/bin/env bash
# Gates objectifs de la factory : ce qui remplace la revue humaine.
#   factory/gates.sh --local     vérifie le working tree courant (agents avant push, ou le board)
#   factory/gates.sh --pr <N>    vérifie la PR N dans un worktree, publie le commit status factory/gates
#   factory/gates.sh --checks    (interne) contrôles de --pr, dans le répertoire courant
#
# Les PR du board (label `board`) ne passent jamais par ici : la factory les ignore et le board
# les merge lui-même. Une PR qui touche un fichier protégé est donc toujours refusée.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
# Chemin absolu de ce script, résolu avant tout cd : en mode --pr, le processus enfant doit être
# ce gates.sh (celui de main), jamais la copie du worktree de la PR.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
# Outillage de confiance (le dossier factory/ de ce script) : ses tests ne dépendent pas de la
# PR, dont le worktree peut précéder un ajout à factory/ sur main.
FACTORY_DIR="$(dirname "$SELF")"
BASE_REF="${BASE_REF:-origin/main}"
COVERAGE_MIN="${COVERAGE_MIN:-80}"
PROTECTED_RE='^(VISION\.md|CLAUDE\.md|docs/(factory|engineering)/|clippy\.toml|deny\.toml|rustfmt\.toml|rust-toolchain\.toml|\.claude/|\.zed/|\.githooks/|\.github/|docker/|docker-compose\.yml|factory/|xtask/|\.cargo/)'
PATTERNS="${GATES_PATTERNS:-$ROOT/factory/attribution.patterns}"

step() { printf '\n▶ %s\n' "$*"; }
has_base() { git rev-parse --verify --quiet "$BASE_REF" >/dev/null; }

# Sections du Cargo.toml racine que seul le board peut changer.
policy_sections() {
  awk '/^\[/{ keep = ($0 ~ /^\[(workspace\.lints|profile)/) } keep'
}

check_integrity() {
  step "intégrité (fichiers protégés)"
  has_base || { echo "pas de $BASE_REF : contrôle ignoré"; return 0; }
  local touched
  touched="$(git diff --name-only "$BASE_REF"...HEAD | grep -E "$PROTECTED_RE" || true)"
  if [ -n "$touched" ]; then
    echo "fichiers protégés modifiés :"; echo "$touched"; return 1
  fi
  if ! diff <(git show "$BASE_REF:Cargo.toml" | policy_sections) <(policy_sections <Cargo.toml) >/dev/null; then
    echo "sections [workspace.lints*] ou [profile*] de Cargo.toml modifiées"; return 1
  fi
}

# Aucune attribution IA : seul le compte du board apparaît sur GitHub.
check_attribution() {
  local extra="${1:-}"
  step "attribution"
  local text=""
  has_base && text="$(git log --format='%an <%ae>%n%cn <%ce>%n%B' "$BASE_REF"..HEAD)"
  text="$text"$'\n'"$extra"
  if grep -niE -f "$PATTERNS" <<<"$text"; then
    echo "attribution IA trouvée (commits, titre ou description de PR)"; return 1
  fi
}

run_mutants_on_diff() {
  local diff_file
  diff_file="$(mktemp)"
  git diff "$BASE_REF"...HEAD -- 'crates/**/*.rs' >"$diff_file"
  if [ -s "$diff_file" ]; then
    step "mutation (code modifié)"
    cargo mutants --in-diff "$diff_file" --workspace --exclude 'xtask/**'
  else
    echo "pas de code Rust modifié : mutation ignorée"
  fi
}

# Mode --pr : fusionne la base dans le worktree de la PR pour juger ce que le merge produirait.
# Fusion locale, jamais poussée ; identité passée en -c, sans hook ni signature, aucune config
# modifiée. Conflit : échec avec un message explicite.
merge_base() {
  step "fusion avec $BASE_REF"
  if ! git -c user.name="factory gates" -c user.email=gates@localhost.invalid \
      -c core.hooksPath=/dev/null -c commit.gpgsign=false \
      merge --no-edit "$BASE_REF" >/dev/null 2>&1; then
    git merge --abort >/dev/null 2>&1 || true
    echo "branche en conflit avec main : à mettre à jour"
    return 1
  fi
  echo "fusion locale avec $BASE_REF : $(git rev-parse --short HEAD) (jamais poussée)"
}

run_gates() {
  # Tests de l'outillage : depuis FACTORY_DIR. check-modes.sh, lui, vérifie l'index du répertoire
  # courant (le worktree de la PR en mode --pr).
  step "modes";         bash "$FACTORY_DIR/check-modes.test.sh"
                        bash "$FACTORY_DIR/check-modes.sh"
  step "hooks";         bash "$FACTORY_DIR/hooks/guard.test.sh"
                        bash "$FACTORY_DIR/orchestrator.test.sh"
                        bash "$FACTORY_DIR/orchestrator-notify.test.sh"
                        bash "$FACTORY_DIR/orchestrator-stall.test.sh"
  step "format";        cargo fmt --all --check
  step "lints";         cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
  step "tests";         cargo test --workspace --all-features --locked
  step "architecture";  cargo xtask arch
  step "supply chain";  cargo deny check
  step "couverture";    cargo llvm-cov --workspace --exclude xtask --all-features --locked \
                          --fail-under-lines "$COVERAGE_MIN" --summary-only
  if has_base; then
    run_mutants_on_diff
  fi
}

post_status() {
  local sha="$1" state="$2" desc="$3"
  gh api "repos/{owner}/{repo}/statuses/$sha" \
    -f state="$state" -f context=factory/gates -f description="$desc" >/dev/null
}

case "${1:-}" in
  --local)
    cd "$ROOT"
    if [ "${FACTORY_AGENT:-0}" = "1" ]; then check_integrity; fi
    check_attribution
    run_gates
    echo; echo "✓ gates verts"
    ;;
  --checks)
    # Processus enfant lancé par --pr : ici, set -e s'applique à chaque étape. Dans la condition
    # d'un if, bash ignore set -e (même dans un sous-shell) : une étape rouge passerait inaperçue.
    # Intégrité et attribution sur la tête de la PR ; gates sur sa fusion avec la base.
    check_integrity
    check_attribution "${GATES_PR_TEXT:-}"
    merge_base
    run_gates
    ;;
  --pr)
    pr="${2:?numéro de PR requis}"
    cd "$ROOT"
    wt="$(mktemp -d)/pr-$pr"
    git fetch --quiet origin "pull/$pr/head:gates/pr-$pr" --force
    git fetch --quiet origin "${BASE_REF#origin/}"  # base à jour pour la fusion de --checks
    git worktree add --quiet --force "$wt" "gates/pr-$pr"
    trap 'git -C "$ROOT" worktree remove --force "$wt"' EXIT
    cd "$wt"
    sha="$(git rev-parse HEAD)"
    pr_text="$(gh pr view "$pr" --json title,body --jq '.title + "\n" + .body')"
    post_status "$sha" pending "gates en cours"
    if GATES_PR_TEXT="$pr_text" GATES_PATTERNS="$PATTERNS" bash "$SELF" --checks; then
      post_status "$sha" success "tous les gates sont verts"
      echo "✓ gates verts sur $sha"
    else
      post_status "$sha" failure "au moins un gate est rouge"
      exit 1
    fi
    ;;
  *)
    echo "usage : $0 --local | --pr <N>" >&2; exit 2 ;;
esac
