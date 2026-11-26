#!/usr/bin/env bash
# Rattache l'issue <enfant> comme sub-issue de <parent> (API REST GitHub ; gh n'a pas de flag natif).
set -euo pipefail
parent="${1:?usage : link-sub-issue.sh <parent> <enfant>}"
child="${2:?usage : link-sub-issue.sh <parent> <enfant>}"
child_id="$(gh api "repos/{owner}/{repo}/issues/$child" --jq .id)"
gh api -X POST "repos/{owner}/{repo}/issues/$parent/sub_issues" -F sub_issue_id="$child_id" --jq '.number' >/dev/null
echo "#$child rattachée à #$parent"
