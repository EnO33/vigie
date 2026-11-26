#!/usr/bin/env bash
# Échoue si un script (*.sh) ou un hook Git (.githooks/*) n'est pas en 100755 dans l'index.
# Cause : sous Windows (core.fileMode=false), git enregistre les nouveaux fichiers en 100644 ;
# sous Linux (conteneur), git ignore alors les hooks et refuse d'exécuter les scripts.
#   bash factory/check-modes.sh      (tests : bash factory/check-modes.test.sh)
set -euo pipefail

# Format de « git ls-files -s » : <mode> <objet> <étape>\t<chemin>
bad="$(git ls-files -s -- '*.sh' '.githooks/*' | awk -F '\t' '{ split($1, m, " "); if (m[1] != "100755") print m[1] "  " $2 }')"
if [ -n "$bad" ]; then
  echo "fichiers non exécutables dans l'index (attendu 100755) :"
  echo "$bad"
  echo "correction : git update-index --chmod=+x <fichier>"
  exit 1
fi
echo "modes : scripts et hooks en 100755"
