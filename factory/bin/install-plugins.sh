#!/usr/bin/env bash
# Installe les plugins/skills de factory/plugins.lock, chacun au SHA exact épinglé.
# Clone local au SHA → marketplace locale → install. Aucune résolution de « latest » ici.
set -euo pipefail

LOCK="${1:?usage : install-plugins.sh <plugins.lock>}"
DEST="${PLUGINS_DIR:-$HOME/.factory-plugins}"
SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$DEST" "$SKILLS_DIR"

grep -vE '^\s*(#|$)' "$LOCK" | while read -r repo sha target _; do
  dir="$DEST/${repo//\//__}"
  rm -rf "$dir"
  git init --quiet "$dir"
  git -C "$dir" fetch --quiet --depth 1 "https://github.com/$repo.git" "$sha"
  git -C "$dir" checkout --quiet FETCH_HEAD
  got="$(git -C "$dir" rev-parse HEAD)"
  [ "$got" = "$sha" ] || { echo "SHA inattendu pour $repo : $got" >&2; exit 1; }

  case "$target" in
    skill:*)
      path="${target#skill:}"
      name="$(basename "$path")"
      rm -rf "${SKILLS_DIR:?}/$name"
      cp -R "$dir/$path" "$SKILLS_DIR/$name"
      echo "skill $name ← $repo@${sha:0:7}"
      ;;
    *@*)
      claude plugin marketplace add "$dir"
      claude plugin install "$target"
      echo "plugin $target ← $repo@${sha:0:7}"
      ;;
    *)
      echo "cible invalide : $target" >&2; exit 1 ;;
  esac
done
