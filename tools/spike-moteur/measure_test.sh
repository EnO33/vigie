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

# Instance longue : sans SIGKILL, l'arrêt attendrait les 300 s.
SECONDS=0
out="$($M startup --runs 1 -- sh -c 'trap "" TERM; echo VIGIE_SPIKE_READY; sleep 300')" || fail "SIGTERM ignoré"
[ "$SECONDS" -lt 10 ] || fail "SIGKILL non envoyé : ${SECONDS}s"
leftovers 'sleep 300' && fail "SIGKILL non envoyé : instance survivante"

# Descendant qui change de groupe (set -m) : tué quand même (arrêt par session).
$M startup --runs 1 -- bash -c 'set -m; sleep 51 & set +m; echo VIGIE_SPIKE_READY; sleep 52' >/dev/null || fail "setpgid"
leftovers 'sleep 5[12]' && fail "descendant setpgid survivant"

$M startup -- true 2>/dev/null && fail "argument manquant accepté"

out="$($M memory --settle 1 -- sh -c 'sleep 34 & sleep 34 & echo VIGIE_SPIKE_READY; wait')" || fail "memory"
mb="$(sed -n 's/^memory_rss_mb=//p' <<<"$out")"
[ -n "$mb" ] || fail "memory_rss_mb absent"
grep -q '^env_nproc=' <<<"$out" || fail "environnement absent (memory)"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# Somme des RSS de l'arbre : le chef est léger, deux descendants tiennent ~40 Mo chacun.
printf '%s\n' 'x=$(head -c 40000000 /dev/zero | tr "\0" a); sleep 35' >"$T/alloc.sh"
out="$($M memory --settle 2 -- sh -c "bash $T/alloc.sh & bash $T/alloc.sh & sleep 1; echo VIGIE_SPIKE_READY; wait")" || fail "memory arbre"
mb="$(sed -n 's/^memory_rss_mb=//p' <<<"$out")"
[ "${mb:-0}" -ge 75 ] || fail "somme des RSS de l'arbre trop faible : '$mb' Mo (attendu >= 75)"
leftovers 'sleep 35' && fail "descendant survivant après memory"

# Course : des processus éphémères apparaissent et disparaissent pendant le scan de /proc.
churn=()
for _ in 1 2 3 4; do ( while :; do /bin/true; done ) & churn+=($!); done
for i in 1 2 3 4 5; do
  out="$($M memory --settle 0.2 -- sh -c 'echo VIGIE_SPIKE_READY; sleep 36')" || { kill "${churn[@]}"; fail "memory sous course (essai $i)"; }
  grep -qE '^memory_rss_mb=[0-9]+$' <<<"$out" || { kill "${churn[@]}"; fail "memory_rss_mb absent sous course (essai $i)"; }
done
kill "${churn[@]}"; wait "${churn[@]}" 2>/dev/null

# Médiane (moyenne des deux valeurs du milieu si N est pair).
( source ./measure.sh
  [ "$(median 100 200 300 1000)" = 250 ] && [ "$(median 300 100 200)" = 200 ] && [ "$(median 7)" = 7 ] ) || fail "médiane"

# Arguments numériques invalides : erreur claire, code 2.
for bad in "startup --runs 0" "startup --runs abc" "startup --runs 1 --timeout abc" "memory --settle abc"; do
  err="$($M $bad -- true 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] && grep -q '^measure.sh: --' <<<"$err" || fail "argument invalide accepté ou erreur cryptique ($bad) : rc=$rc $err"
done

# SIGTERM sur measure.sh : l'instance ne survit pas.
$M memory --settle 20 -- sh -c 'echo VIGIE_SPIKE_READY; sleep 41; true' >/dev/null 2>&1 &
mp=$!; sleep 1.5; kill -TERM "$mp"; wait "$mp"; rc=$?
[ "$rc" -eq 143 ] || fail "SIGTERM : code $rc au lieu de 143"
leftovers 'sleep 41' && fail "instance survivante après SIGTERM sur measure.sh"
leftovers 'sleep 20' && fail "attente de stabilisation survivante après SIGTERM sur measure.sh"

# Deux TERM de suite pendant l'arrêt : le KILL part quand même (instance qui ignore TERM).
$M memory --settle 20 -- sh -c 'trap "" TERM; echo VIGIE_SPIKE_READY; sleep 53' >/dev/null 2>&1 &
mp=$!; sleep 1.5; kill -TERM "$mp"; sleep 0.3; kill -TERM "$mp"; wait "$mp"
leftovers 'sleep 53' && fail "instance survivante après double SIGTERM"

# Instance morte pendant --settle : message clair.
err="$($M memory --settle 1 -- sh -c 'echo VIGIE_SPIKE_READY' 2>&1)" && fail "mort pendant settle : code 0"
grep -q 'settle' <<<"$err" || fail "message settle peu clair : $err"

err="$(VIGIE_STRACE=strace-inexistant $M network --duration 1 -- true 2>&1)" && fail "strace absent : code 0"
grep -q 'strace absent' <<<"$err" || fail "strace absent non signalé"

# Faux strace : trace écrite d'après le format SUPPOSÉ de strace (non vérifié contre le vrai).
# Teste le filtrage (AF_UNIX/AF_NETLINK exclus, sendmmsg compté) et l'extraction des adresses.
cat >"$T/fakestrace" <<'FAKE'
#!/usr/bin/env bash
while [ "$1" != -o ]; do shift; done
trace="$2"; shift 2
cat >"$trace" <<'TRACE'
100 connect(3, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("93.184.216.34")}, 16) = 0
100 connect(4, {sa_family=AF_UNIX, sun_path="/run/user/1000/wayland-0"}, 25) = 0
100 sendmsg(5, {msg_name={sa_family=AF_NETLINK, nl_pid=0, nl_groups=00000000}, msg_namelen=12}, 0) = 20
101 sendmmsg(6, [{msg_hdr={msg_name={sa_family=AF_INET, sin_port=htons(53), sin_addr=inet_addr("1.1.1.1")}}}], 1, 0) = 1
102 connect(7, {sa_family=AF_INET6, sin6_port=htons(443), sin6_flowinfo=htonl(0), inet_pton(AF_INET6, "2001:db8::1", &sin6_addr), sin6_scope_id=0}, 28) = 0
TRACE
exec "$@"
FAKE
chmod +x "$T/fakestrace"
out="$(VIGIE_STRACE="$T/fakestrace" $M network --duration 0.2 -- sh -c 'echo VIGIE_SPIKE_READY')" || fail "network (faux strace)"
grep -qx 'network_calls=3' <<<"$out" || fail "network_calls attendu 2 : $out"
grep -qx 'network_dest=93.184.216.34:443' <<<"$out" && grep -qx 'network_dest=1.1.1.1:53' <<<"$out" && grep -qx 'network_dest=\[2001:db8::1\]:443' <<<"$out" || fail "adresses : $out"
grep -q 'wayland' <<<"$out" && fail "AF_UNIX listé"

if command -v strace >/dev/null; then
  out="$($M network --duration 2 -- bash -c 'echo VIGIE_SPIKE_READY; exec 3<>/dev/tcp/127.0.0.1/9; sleep 5')" || fail "network"
  grep -q '^network_dest=127.0.0.1:9$' <<<"$out" || fail "adresse absente : $out"
else
  echo "SKIP: test network (strace absent)"
fi
echo "OK"
