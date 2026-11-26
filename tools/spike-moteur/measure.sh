#!/usr/bin/env bash
# Mesure reproductible d'un prototype de moteur (voir l'issue #16 pour le contrat).
#   measure.sh startup --runs N [--timeout T] -- cmd…
#   measure.sh memory  --settle S [--timeout T] -- cmd…
#   measure.sh network --duration D [--timeout T] -- cmd…
# Contrat du prototype : écrire VIGIE_SPIKE_READY seul sur une ligne de stdout quand sa première
# page est affichée, et VIDER son tampon (flush) juste après : stdout est un fichier, donc
# bufferisé par blocs en C ou Python. À défaut, envelopper la commande avec `stdbuf -oL`.
# Linux uniquement (/proc, setsid). Mesure et arrêt portent sur la session de l'instance : un
# descendant qui change de groupe (setpgid) y reste, un qui crée sa propre session (setsid) y échappe.

die() { echo "measure.sh: $*" >&2; exit 2; }

# now : met l'heure murale en ms dans NOW_MS, sans fork ($EPOCHREALTIME, bash >= 5).
now() { local t="${EPOCHREALTIME//[.,]/}"; NOW_MS=$(( t / 1000 )); }

# alive <pid> : le processus existe et n'est pas un zombie (3e ligne de status : « State: … »).
alive() { local st; { read -r; read -r; read -r _ st; } 2>/dev/null <"/proc/$1/status" && [[ $st != Z* ]]; }

# has_ready <fichier> : une ligne est exactement VIGIE_SPIKE_READY.
has_ready() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do [ "$line" = VIGIE_SPIKE_READY ] && return 0; done 2>/dev/null <"$1"
  return 1
}

# median <entier…> : médiane ; moyenne (entière) des deux valeurs du milieu si N est pair.
median() {
  local s=($(printf '%s\n' "$@" | sort -n))
  echo $(( (s[(${#s[@]} - 1) / 2] + s[${#s[@]} / 2]) / 2 ))
}

# Permet à measure_test.sh de charger les fonctions sans lancer de mesure.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

set -euo pipefail

TMP="$(mktemp -d)"
PID=""
# session_pids : pids vivants (hors zombies) de la session de l'instance, même sélection que
# tree_rss_kb. Un descendant qui change de groupe (setpgid, `set -m`) reste dans la session.
session_pids() {
  { cat /proc/[0-9]*/stat 2>/dev/null || true; } |
    awk -v sid="$PID" '{ p = $1; sub(/^.*\) /, ""); if ($4 == sid && $1 != "Z") print p }'
}
# Tue toute la session de l'instance : TERM, puis KILL si elle s'obstine ou laisse des orphelins.
stop() {
  [ -n "$PID" ] || return 0
  local pids i; pids="$(session_pids)"
  [ -z "$pids" ] || kill -TERM $pids 2>/dev/null || true
  for ((i = 0; i < 20; i++)); do [ -z "$(session_pids)" ] && break; nap 0.1; done
  pids="$(session_pids)"
  [ -z "$pids" ] || kill -KILL $pids 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=""
}
# Signaux ignorés pendant le nettoyage : un 2e TERM/INT ne doit pas couper l'envoi du KILL.
cleanup() { trap '' INT TERM; stop; rm -rf "$TMP"; }
# EXIT lance cleanup, y compris via ces deux traps (un signal tué sans trap laisserait l'instance).
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# nap <secondes> : attente sans fork et interrompue tout de suite par un signal piégé
# (`sleep` en avant-plan retarderait le trap jusqu'à sa fin).
mkfifo "$TMP/nap"
exec 9<>"$TMP/nap"
nap() { read -r -t "$1" -u 9 || true; }

# spawn <fichier de sortie> cmd… : lance dans son propre groupe, PID = chef de groupe.
spawn() {
  local out="$1"; shift
  : >"$out" # vide avant le lancement : sinon le READY du tour précédent est relu
  setsid "$@" >"$out" &
  PID=$!
}

# wait_ready <fichier> : attend VIGIE_SPIKE_READY ; échoue sur timeout ou mort prématurée.
wait_ready() {
  now; local deadline=$(( NOW_MS + TIMEOUT * 1000 ))
  until has_ready "$1"; do
    if ! alive "$PID"; then
      has_ready "$1" && return 0 # READY écrit juste avant la sortie
      stop; die "la commande s'est arrêtée avant VIGIE_SPIKE_READY"
    fi
    now; [ "$NOW_MS" -lt "$deadline" ] || { stop; die "VIGIE_SPIKE_READY absent après ${TIMEOUT}s"; }
    nap 0.01
  done
}

# Somme des RSS (ko) de la session de l'instance, lue dans /proc/<pid>/stat (champ 6 = session,
# champ 24 = RSS en pages). Un fichier qui disparaît pendant la lecture est ignoré.
tree_rss_kb() {
  { cat /proc/[0-9]*/stat 2>/dev/null || true; } |
    awk -v sid="$PID" -v page="$(getconf PAGESIZE)" '
      { sub(/^.*\) /, ""); if ($4 == sid) sum += $22 }   # retire « pid (comm) » : champs décalés de 2
      END { printf "%d\n", sum * page / 1024 }'
}

environment() {
  echo "env_uname=$(uname -srm)"
  echo "env_nproc=$(nproc)"
  echo "env_memtotal_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
}

[ $# -ge 1 ] || die "usage: measure.sh startup|memory|network [options] -- commande…"
MODE="$1"; shift
RUNS=""; SETTLE=""; DURATION=""; TIMEOUT=30
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  [ $# -ge 2 ] || die "valeur manquante pour $1"
  case "$1" in
    --runs)     [[ $2 =~ ^[1-9][0-9]*$ ]] || die "--runs : entier > 0 attendu, reçu '$2'"; RUNS="$2" ;;
    --timeout)  [[ $2 =~ ^[1-9][0-9]*$ ]] || die "--timeout : entier > 0 attendu, reçu '$2'"; TIMEOUT="$2" ;;
    --settle)   [[ $2 =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "--settle : durée en secondes attendue, reçu '$2'"; SETTLE="$2" ;;
    --duration) [[ $2 =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "--duration : durée en secondes attendue, reçu '$2'"; DURATION="$2" ;;
    *) die "option inconnue : $1" ;;
  esac
  shift 2
done
[ "${1:-}" = "--" ] || die "séparateur -- manquant"
shift
[ $# -ge 1 ] || die "commande manquante après --"

case "$MODE" in
  startup)
    [ -n "$RUNS" ] || die "--runs requis"
    samples=()
    for ((r = 0; r < RUNS; r++)); do
      now; t0="$NOW_MS"; spawn "$TMP/out" "$@"; wait_ready "$TMP/out"
      now; samples+=($(( NOW_MS - t0 ))); stop
    done
    sorted=($(printf '%s\n' "${samples[@]}" | sort -n))
    echo "startup_median_ms=$(median "${samples[@]}")"
    echo "startup_min_ms=${sorted[0]}"
    echo "startup_max_ms=${sorted[$(( ${#sorted[@]} - 1 ))]}" ;;
  memory)
    [ -n "$SETTLE" ] || die "--settle requis"
    spawn "$TMP/out" "$@"; wait_ready "$TMP/out"; nap "$SETTLE"
    alive "$PID" || die "la commande s'est arrêtée pendant --settle"
    kb="$(tree_rss_kb)"
    [[ $kb =~ ^[0-9]+$ ]] && [ "$kb" -gt 0 ] || die "mesure mémoire illisible : '$kb'"
    echo "memory_rss_mb=$(( kb / 1024 ))" ;;
  network)
    [ -n "$DURATION" ] || die "--duration requis"
    STRACE="${VIGIE_STRACE:-strace}"
    command -v "$STRACE" >/dev/null || die "strace absent : mesure réseau impossible"
    spawn "$TMP/out" "$STRACE" -f -e trace=connect,sendto,sendmsg,sendmmsg -o "$TMP/trace" "$@"
    wait_ready "$TMP/out"; nap "$DURATION"; stop
    # Seules les familles AF_INET/AF_INET6 : AF_UNIX et AF_NETLINK (Wayland, D-Bus…) ne sont pas du réseau.
    # Limite : un send() sans adresse sur socket déjà connectée n'est pas tracé ici.
    echo "network_calls=$(grep -cE '^[0-9]+ +(connect|sendto|sendmsg|sendmmsg)\(.*sa_family=AF_INET6?,' "$TMP/trace" || true)"
    sed -nE 's/.*sin6?_port=htons\(([0-9]+)\).*inet_addr\("([^"]+)"\).*/\2:\1/p; s/.*sin6_port=htons\(([0-9]+)\).*"([^"]+)", &sin6_addr.*/[\2]:\1/p' "$TMP/trace" |
      sort -u | sed 's/^/network_dest=/' ;;
  *) die "mode inconnu : $MODE" ;;
esac
environment
