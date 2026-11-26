#!/usr/bin/env bash
# Tests des notifications ntfy de factory/orchestrator.sh.
#   bash factory/orchestrator-notify.test.sh
# curl, gh et claude factices : on vérifie les en-têtes envoyés, une seule notification par
# transition de pause, qu'un ntfy injoignable ne casse rien et que les agents ne voient pas ntfy.
set -uo pipefail

ORCH="$(cd "$(dirname "$0")" && pwd)/orchestrator.sh"
ORIG_PATH="$PATH"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FAKE="$TMP/fake"
mkdir -p "$TMP/bin" "$FAKE" "$TMP/work/factory"
failures=0

# curl factice : un appel = fichiers argv.N, headers.N (y compris « -H @fichier »), url.N, body.N.
cat >"$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE/n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FAKE/n"
printf '%s\n' "$*" >"$FAKE/argv.$n"
: >"$FAKE/headers.$n"
while [ $# -gt 0 ]; do
  case "$1" in
    -H) if [ "${2#@}" != "$2" ]; then cat "${2#@}" >>"$FAKE/headers.$n"
        else printf '%s\n' "$2" >>"$FAKE/headers.$n"; fi; shift 2 ;;
    --data-binary) printf '%s' "$2" >"$FAKE/body.$n"; shift 2 ;;
    -m|-o|-w) shift 2 ;;
    -*) shift ;;
    *) printf '%s' "$1" >"$FAKE/url.$n"; shift ;;
  esac
done
printf '%s' "${FAKE_CURL_CODE:-200}"
exit "${FAKE_CURL_RC:-0}"
EOF
# gh factice : réponses finales (le --jq du vrai gh est supposé appliqué).
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"--label factory:halt"*) c="$(cat "$FAKE/halt")"; [ "$c" = erreur ] && exit 1; echo "$c" ;;
  *"--label type:report"*) echo "https://github.com/test/vigie/issues/5" ;;
  *"pr list"*"--state merged"*) echo 2 ;;
  *"pr list"*"--state open"*) echo 3 ;;
  *"pr view"*headRefOid*) echo abc123 ;;
  *"pr view"*"--json title"*) echo "fix: titre de la PR" ;;
  *"pr view"*"--json body"*) echo "Closes #2" ;;
  "pr merge"*) exit "${FAKE_MERGE_RC:-0}" ;;
  *) exit 0 ;;
esac
EOF
# claude factice : note les variables ntfy qu'il voit.
cat >"$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "${NTFY_TOPIC-absent}|${NTFY_TOKEN-absent}" >"$FAKE/claude-env"
exit "${FAKE_CLAUDE_RC:-0}"
EOF
chmod +x "$TMP/bin/curl" "$TMP/bin/gh" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

export REPO=test/vigie GIT_AUTHOR_EMAIL=t@example.invalid LOG_DIR="$TMP/logs" STATE_DIR="$TMP/state" \
  WORKDIR="$TMP/work" BACKOFF_SECONDS=0 NTFY_URL="https://ntfy.example/" NTFY_TOPIC="vigie-test"
unset NTFY_TOKEN
# shellcheck source=orchestrator.sh
source "$ORCH"
set +e  # orchestrator.sh active set -e : le test gère lui-même ses échecs.

calls() { cat "$FAKE/n" 2>/dev/null || echo 0; }
reset() { rm -f "$FAKE"/*; }
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; failures=$((failures + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 : « $3 », attendu « $2 »"; fi; }
has_header() { grep -qxF "$2" "$FAKE/headers.$1"; }

# --- désactivé sans topic
reset; NTFY_TOPIC="" notify "x" default rocket
expect "NTFY_TOPIC vide : aucun envoi" 0 "$(calls)"

# --- en-têtes, URL, corps, jeton hors des arguments
reset; NTFY_TOKEN="tk_secret_test" notify "Gates rouges : PR #7" high x "https://github.com/test/vigie/pull/7" "Renvoyée."
expect "un envoi" 1 "$(calls)"
for h in "Title: Gates rouges : PR #7" "Priority: high" "Tags: x" "Click: https://github.com/test/vigie/pull/7" \
         "Authorization: Bearer tk_secret_test"; do
  if has_header 1 "$h"; then ok "en-tête « $h »"; else ko "en-tête « $h » absent"; fi
done
expect "URL = NTFY_URL/NTFY_TOPIC" "https://ntfy.example/vigie-test" "$(cat "$FAKE/url.1")"
expect "corps du message" "Renvoyée." "$(cat "$FAKE/body.1")"
if grep -q tk_secret_test "$FAKE/argv.1"; then ko "le jeton apparaît dans les arguments de curl"
else ok "jeton absent des arguments de curl"; fi

# --- sans jeton ni lien : ni Authorization ni Click ; corps = titre
reset; notify "Factory démarrée" default rocket
if grep -qE '^(Authorization|Click):' "$FAKE/headers.1"; then ko "Authorization ou Click envoyé sans raison"
else ok "sans jeton ni lien : ni Authorization ni Click"; fi
expect "corps par défaut = titre" "Factory démarrée" "$(cat "$FAKE/body.1")"

# --- pause : une seule notification par transition
reset; echo 1 >"$FAKE/halt"
r=""; for _ in 1 2 3; do halt_gate; r="$r$?"; done
expect "halt ouverte : pause à chaque tick" "000" "$r"
expect "halt ouverte : une seule notification" 1 "$(calls)"
has_header 1 "Title: Factory en pause" && ok "titre « Factory en pause »" || ko "titre de pause"
echo 0 >"$FAKE/halt"
r=""; for _ in 1 2 3; do halt_gate; r="$r$?"; done
expect "halt levée : reprise à chaque tick" "111" "$r"
expect "halt levée : une seule notification de plus" 2 "$(calls)"
has_header 2 "Title: Factory relancée" && ok "titre « Factory relancée »" || ko "titre de reprise"
echo erreur >"$FAKE/halt"
halt_gate; expect "état illisible : pause par prudence" 0 "$?"
expect "état illisible : aucune notification" 2 "$(calls)"

# --- ntfy injoignable : notify réussit quand même, sous set -e, et logge sans le topic
reset
out="$( (set -e; FAKE_CURL_RC=7 FAKE_CURL_CODE=000 notify "t" high warning; echo "suite") 2>&1 )"
case "$out" in *suite*) ok "curl en échec (code 7) : la suite tourne" ;; *) ko "curl en échec casse l'appelant" ;; esac
case "$out" in *"non envoyée"*) ok "échec loggé" ;; *) ko "échec non loggé" ;; esac
case "$out" in *vigie-test*|*ntfy.example*) ko "le log d'échec expose l'URL ou le topic" ;; *) ok "log d'échec sans URL ni topic" ;; esac
out="$( (set -e; FAKE_CURL_CODE=500 notify "t" high warning; echo "suite") 2>&1 )"
case "$out" in *suite*"non envoyée"*|*"non envoyée"*suite*) ok "HTTP 500 : loggé, la suite tourne" ;; *) ko "HTTP 500 mal géré" ;; esac
out="$( (set -e; PATH="$ORIG_PATH" NTFY_URL="http://127.0.0.1:9" notify "t" high warning; echo "suite") 2>&1 )"
case "$out" in *suite*) ok "vrai curl, port fermé : la suite tourne" ;; *) ko "vrai curl injoignable casse l'appelant" ;; esac

# --- agents : ni NTFY_TOPIC ni NTFY_TOKEN ; échec = notification high
reset; NTFY_TOKEN="tk_secret_test" run_agent developer "Mission : test." >/dev/null
expect "agent : variables ntfy retirées" "absent|absent" "$(cat "$FAKE/claude-env")"
expect "agent réussi : aucune notification" 0 "$(calls)"
reset; FAKE_CLAUDE_RC=1 run_agent developer "Mission : test." >/dev/null
expect "agent en échec : une notification" 1 "$(calls)"
has_header 1 "Priority: high" && ok "agent en échec : priorité high" || ko "agent en échec : priorité"

# --- merge et gates (gates.sh factice dans WORKDIR)
printf '#!/usr/bin/env bash\nexit "${FAKE_GATES_RC:-0}"\n' >"$TMP/work/factory/gates.sh"
reset; merge_if_green 7 >/dev/null
expect "PR mergée : une notification" 1 "$(calls)"
has_header 1 "Click: https://github.com/test/vigie/pull/7" && ok "PR mergée : lien vers la PR" || ko "PR mergée : lien"
reset; FAKE_MERGE_RC=1 merge_if_green 7 >/dev/null
expect "merge refusé par GitHub : pas de notification « mergée »" 0 "$(calls)"
reset; FAKE_GATES_RC=1 merge_if_green 7 >/dev/null
expect "gates rouges : une notification" 1 "$(calls)"
has_header 1 "Priority: high" && ok "gates rouges : priorité high" || ko "gates rouges : priorité"

# --- rapport hebdomadaire (low, lien) et signe de vie quotidien (min, une fois par jour)
reset; notify_weekly_report
has_header 1 "Priority: low" && has_header 1 "Click: https://github.com/test/vigie/issues/5" \
  && ok "rapport hebdo : low + lien" || ko "rapport hebdo"
reset; rm -f "$STATE_DIR/last-heartbeat"; heartbeat; heartbeat
expect "signe de vie : une fois par jour" 1 "$(calls)"
has_header 1 "Priority: min" && ok "signe de vie : priorité min" || ko "signe de vie : priorité"
case "$(cat "$FAKE/body.1")" in *"Merges (24 h) : 2"*"PR ouvertes : 3"*) ok "signe de vie : merges et PR ouvertes" ;;
  *) ko "signe de vie : contenu « $(cat "$FAKE/body.1") »" ;; esac

echo
if [ "$failures" -eq 0 ]; then echo "✓ notifications ntfy : tous les tests passent"
else echo "✗ notifications ntfy : $failures échec(s)"; exit 1; fi
