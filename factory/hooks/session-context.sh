#!/usr/bin/env bash
# Hook SessionStart : injecte la réalité du moment dans le contexte de l'agent
# (date, toolchain, versions résolues) pour contrer sa date de coupure.
set -uo pipefail
echo "## Contexte factuel (injecté au démarrage, prioritaire sur ta mémoire)"
echo "- Date du jour : $(date +%F)"
echo "- $(rustc -V 2>/dev/null || echo 'rustc absent')"
echo "- $(cargo -V 2>/dev/null || echo 'cargo absent')"
echo "- Dépendances directes résolues (Cargo.lock) :"
cargo tree --workspace --depth 1 --edges normal --prefix none 2>/dev/null \
  | grep -v ' (/' | grep -v '^vigie-\|^xtask' | sort -u | sed 's/^/  - /'
echo "- Ta connaissance des API peut être périmée : vérifie dans ~/.cargo/registry/src/ (docs/engineering/FRESHNESS.md)."
