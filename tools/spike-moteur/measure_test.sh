#!/usr/bin/env bash
# Tests de measure.sh avec des commandes factices ; sort au premier écart.
set -uo pipefail
cd "$(dirname "$0")"
M=./measure.sh
fail() { echo "FAIL: $*" >&2; exit 1; }
leftovers() { pgrep -fa "$1" >&2; pgrep -f "$1" >/dev/null; }

bash -n measure.sh && bash -n measure_test.sh || fail "bash -n"

out="$($M startup --runs 5 -- sh -c 'sleep 0.2; echo VIGIE_SPIKE_READY; sleep 31')" || fail "startup"
med="$(sed -n 's/^startup_median_ms=//p' <<<"$out")"
[ "$med" -ge 150 ] && [ "$med" -le 1000 ] || fail "médiane hors bornes : $med"
grep -q '^env_uname=' <<<"$out" && grep -q '^env_nproc=' <<<"$out" && grep -q '^env_memtotal_kb=' <<<"$out" || fail "environnement absent"
leftovers 'sleep 31' && fail "instance survivante après startup"

err="$($M startup --runs 1 --timeout 1 -- sh -c 'sleep 32' 2>&1)" && fail "timeout : code 0"
grep -q 'VIGIE_SPIKE_READY' <<<"$err" || fail "message de timeout peu clair : $err"
leftovers 'sleep 32' && fail "enfant survivant après timeout"

$M startup --runs 1 -- sh -c 'exit 3' 2>/dev/null && fail "mort avant READY : code 0"

out="$($M startup --runs 1 -- sh -c 'trap "" TERM; echo VIGIE_SPIKE_READY; sleep 33')" || fail "SIGTERM ignoré"
leftovers 'sleep 33' && fail "SIGKILL non envoyé"

$M startup -- true 2>/dev/null && fail "argument manquant accepté"

out="$($M memory --settle 1 -- sh -c 'sleep 34 & sleep 34 & echo VIGIE_SPIKE_READY; wait')" || fail "memory"
mb="$(sed -n 's/^memory_rss_mb=//p' <<<"$out")"
[ -n "$mb" ] || fail "memory_rss_mb absent"
grep -q '^env_nproc=' <<<"$out" || fail "environnement absent (memory)"

err="$(VIGIE_STRACE=strace-inexistant $M network --duration 1 -- true 2>&1)" && fail "strace absent : code 0"
grep -q 'strace absent' <<<"$err" || fail "strace absent non signalé"

if command -v strace >/dev/null; then
  out="$($M network --duration 2 -- bash -c 'echo VIGIE_SPIKE_READY; exec 3<>/dev/tcp/127.0.0.1/9; sleep 5')" || fail "network"
  grep -q '^network_dest=127.0.0.1:9$' <<<"$out" || fail "adresse absente : $out"
else
  echo "SKIP: test network (strace absent)"
fi
echo "OK"
