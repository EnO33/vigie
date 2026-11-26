#!/usr/bin/env bash
# Exécute une commande dans l'image des agents, sur le dépôt local monté en /workspace/repo.
# Mêmes outils, mêmes versions que la factory : un résultat vert ici est vert là-bas.
#   factory/bin/in-agent-image.sh bash factory/gates.sh --local
#   factory/bin/in-agent-image.sh cargo mutants --workspace --exclude 'xtask/**'
set -euo pipefail

IMAGE="${VIGIE_IMAGE:-vigie-agent:dev}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "image $IMAGE absente : construction (docker compose build)"
  docker compose build
fi

# Chemin hôte au format attendu par Docker Desktop (Windows) ou tel quel (Linux, macOS).
host_root="$(pwd -W 2>/dev/null || pwd)"
tty_flag=()
[ -t 0 ] && [ -t 1 ] && tty_flag=(-it)

MSYS_NO_PATHCONV=1 exec docker run --rm "${tty_flag[@]}" \
  --entrypoint bash \
  -v "$host_root:/workspace/repo" \
  -v vigie-cargo-registry:/usr/local/cargo/registry \
  -v vigie-target:/workspace/target \
  -e CARGO_TARGET_DIR=/workspace/target \
  -w /workspace/repo \
  "$IMAGE" \
  -c 'git config --global --add safe.directory /workspace/repo && exec "$@"' -- "$@"
