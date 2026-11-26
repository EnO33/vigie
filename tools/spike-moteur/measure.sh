#!/usr/bin/env bash
# Mesure reproductible d'un prototype de moteur (voir l'issue #16 pour le contrat).
#   measure.sh startup --runs N [--timeout T] -- cmd…
#   measure.sh memory  --settle S [--timeout T] -- cmd…
#   measure.sh network --duration D [--timeout T] -- cmd…
# Le prototype écrit VIGIE_SPIKE_READY sur stdout quand sa première page est affichée.
set -euo pipefail

die() { echo "measure.sh: $*" >&2; exit 2; }
now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
alive() { [ -d "/proc/$1" ] && ! grep -q '^State:[[:space:]]*Z' "/proc/$1/status" 2>/dev/null; }

TMP="$(mktemp -d)"
PID=""
# Tue tout le groupe de l'instance : TERM, puis KILL si elle s'obstine ou laisse des orphelins.
stop() {
  [ -n "$PID" ] || return 0
  kill -TERM -- "-$PID" 2>/dev/null || true
  for _ in $(seq 1 20); do alive "$PID" || break; sleep 0.1; done
  kill -KILL -- "-$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=""
}
cleanup() { stop; rm -rf "$TMP"; }
trap cleanup EXIT

# spawn <fichier de sortie> cmd… : lance dans son propre groupe, PID = chef de groupe.
spawn() {
  local out="$1"; shift
  setsid "$@" >"$out" &
  PID=$!
}

# wait_ready <fichier> : attend VIGIE_SPIKE_READY ; échoue sur timeout ou mort prématurée.
wait_ready() {
  local deadline=$(( $(now_ms) + TIMEOUT * 1000 ))
  until grep -qx 'VIGIE_SPIKE_READY' "$1" 2>/dev/null; do
    alive "$PID" || { stop; die "la commande s'est arrêtée avant VIGIE_SPIKE_READY"; }
    [ "$(now_ms)" -lt "$deadline" ] || { stop; die "VIGIE_SPIKE_READY absent après ${TIMEOUT}s"; }
    sleep 0.01
  done
}

# Somme des VmRSS (ko) du PID et de tous ses descendants, lue dans /proc/<pid>/status.
tree_rss_kb() {
  awk -v root="$PID" '
    /^Pid:/ { p = $2 } /^PPid:/ { par[p] = $2 } /^VmRSS:/ { rss[p] = $2 }
    END {
      in_tree[root] = 1
      do { grew = 0
        for (q in par) if (!(q in in_tree) && (par[q] in in_tree)) { in_tree[q] = 1; grew = 1 }
      } while (grew)
      for (q in in_tree) sum += rss[q]
      print sum + 0
    }' /proc/[0-9]*/status 2>/dev/null
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
    --runs) RUNS="$2" ;; --settle) SETTLE="$2" ;; --duration) DURATION="$2" ;; --timeout) TIMEOUT="$2" ;;
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
    for _ in $(seq 1 "$RUNS"); do
      t0="$(now_ms)"; spawn "$TMP/out" "$@"; wait_ready "$TMP/out"
      samples+=($(( $(now_ms) - t0 ))); stop
    done
    sorted=($(printf '%s\n' "${samples[@]}" | sort -n))
    echo "startup_median_ms=${sorted[$(( ${#sorted[@]} / 2 ))]}"
    echo "startup_min_ms=${sorted[0]}"
    echo "startup_max_ms=${sorted[$(( ${#sorted[@]} - 1 ))]}" ;;
  memory)
    [ -n "$SETTLE" ] || die "--settle requis"
    spawn "$TMP/out" "$@"; wait_ready "$TMP/out"; sleep "$SETTLE"
    echo "memory_rss_mb=$(( $(tree_rss_kb) / 1024 ))" ;;
  network)
    [ -n "$DURATION" ] || die "--duration requis"
    STRACE="${VIGIE_STRACE:-strace}"
    command -v "$STRACE" >/dev/null || die "strace absent : mesure réseau impossible"
    spawn "$TMP/out" "$STRACE" -f -e trace=connect,sendto,sendmsg -o "$TMP/trace" "$@"
    wait_ready "$TMP/out"; sleep "$DURATION"; stop
    echo "network_calls=$(grep -cE '^[0-9]+ +(connect|sendto|sendmsg)\(' "$TMP/trace" || true)"
    sed -nE 's/.*sin6?_port=htons\(([0-9]+)\).*inet_addr\("([^"]+)"\).*/\2:\1/p; s/.*sin6_port=htons\(([0-9]+)\).*"([^"]+)", &sin6_addr.*/\2:\1/p' "$TMP/trace" |
      sort -u | sed 's/^/network_dest=/' ;;
  *) die "mode inconnu : $MODE" ;;
esac
environment
