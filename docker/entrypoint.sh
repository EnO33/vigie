#!/usr/bin/env bash
# Démarrage du conteneur : clone le dépôt au premier lancement, puis lance l'orchestrateur.
# Identité Git = celle du board : seul son compte apparaît sur GitHub (aucun compte bot).
set -euo pipefail
: "${GH_TOKEN:?GH_TOKEN requis : token fine-grained du compte du board}"
: "${CLAUDE_CODE_OAUTH_TOKEN:?CLAUDE_CODE_OAUTH_TOKEN requis : claude setup-token}"
: "${REPO:?REPO=owner/nom requis}"
: "${GIT_AUTHOR_NAME:?GIT_AUTHOR_NAME requis : ton nom GitHub}"
: "${GIT_AUTHOR_EMAIL:?GIT_AUTHOR_EMAIL requis : ton adresse noreply GitHub}"

export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
gh auth setup-git
git config --global user.name "$GIT_AUTHOR_NAME"
git config --global user.email "$GIT_AUTHOR_EMAIL"

if [ ! -d /workspace/repo/.git ]; then
  gh repo clone "$REPO" /workspace/repo
fi
# Hook commit-msg du dépôt : refuse toute attribution IA
git -C /workspace/repo config core.hooksPath .githooks

exec bash /workspace/repo/factory/orchestrator.sh
