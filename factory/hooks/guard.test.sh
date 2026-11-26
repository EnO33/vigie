#!/usr/bin/env bash
# Tests du hook PreToolUse factory/hooks/guard.sh (commandes Bash des agents).
#   bash factory/hooks/guard.test.sh
# Un refus du hook = code de sortie 2 ; tout autre code non nul est une erreur du test.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/guard.sh"
failures=0

# Code de sortie du hook pour une commande Bash, avec FACTORY_AGENT donné (1 par défaut).
hook_rc() {
  # Here-string plutôt qu'un pipe : guard.sh peut sortir sans lire stdin (FACTORY_AGENT=0) ;
  # jq échouerait alors en écrivant et pipefail garderait son code.
  FACTORY_AGENT="${2:-1}" bash "$HOOK" <<<"$(jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}')" >/dev/null 2>&1
  echo $?
}

expect_deny() {
  local rc; rc="$(hook_rc "$1")"
  if [ "$rc" = 2 ]; then echo "ok   refusé   : $1"
  else echo "FAIL attendu refusé (code $rc) : $1"; failures=$((failures + 1)); fi
}

expect_allow() {
  local rc; rc="$(hook_rc "$1" "${2:-1}")"
  if [ "$rc" = 0 ]; then echo "ok   autorisé : $1"
  else echo "FAIL attendu autorisé (code $rc) : $1"; failures=$((failures + 1)); fi
}

# gh api vers /merge (et /merges, merge direct de branches)
expect_deny 'gh api -X PUT repos/{owner}/{repo}/pulls/12/merge'
expect_deny 'gh api -X PUT "repos/EnO33/vigie/pulls/12/merge" -f merge_method=squash'
expect_deny 'gh api -X POST repos/{owner}/{repo}/merges -f base=main -f head=feat/1-x'

# gh api vers /statuses
expect_deny 'gh api repos/{owner}/{repo}/statuses/abc123 -f state=success -f context=factory/gates'

# gh api vers /rulesets
expect_deny 'gh api -X POST /repos/EnO33/vigie/rulesets --input ruleset.json'
expect_deny 'gh api -X DELETE repos/{owner}/{repo}/rulesets/28170359'

# gh api vers /interaction-limits
expect_deny 'gh api -X DELETE repos/{owner}/{repo}/interaction-limits'

# gh api vers /branches/*/protection
expect_deny 'gh api -X PUT repos/{owner}/{repo}/branches/main/protection --input p.json'
expect_deny "gh api -X DELETE 'repos/{owner}/{repo}/branches/feat/1-x/protection/required_status_checks'"

# --admin, y compris quand « gh pr merge » est écrit autrement
expect_deny 'gh pr  merge 12 --squash --admin'
expect_deny 'gh  pr merge 12 --admin=true'

# Mutations GraphQL : merge, auto-merge, rulesets, protection de branche
expect_deny "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"PR_x\"}) { clientMutationId } }'"
expect_deny "gh api graphql -f query='mutation { mergeBranch(input: {repositoryId: \"R_x\", base: \"main\", head: \"feat/1-x\"}) { clientMutationId } }'"
expect_deny "gh api graphql -f query='mutation(\$id: ID!) { enablePullRequestAutoMerge(input: {pullRequestId: \$id}) { clientMutationId } }' -f id=PR_x"
expect_deny "gh api graphql -f query='mutation(\$id: ID!) { enablePullRequestAgentMerge(input: {pullRequestId: \$id}) { clientMutationId } }' -f id=PR_x"
expect_deny "gh api graphql -f query='mutation { createRepositoryRuleset(input: {sourceId: \"R_x\", name: \"x\", target: BRANCH, enforcement: DISABLED, rules: []}) { clientMutationId } }'"
expect_deny "gh api graphql -f query='mutation { updateRepositoryRuleset(input: {repositoryRulesetId: \"RRS_x\", enforcement: DISABLED}) { clientMutationId } }'"
expect_deny "gh api graphql -f query='mutation { deleteRepositoryRuleset(input: {repositoryRulesetId: \"RRS_x\"}) { clientMutationId } }'"
expect_deny "gh api graphql -f query='mutation { createBranchProtectionRule(input: {repositoryId: \"R_x\", pattern: \"x\"}) { clientMutationId } }'"
expect_deny "gh api graphql -f query='mutation { updateBranchProtectionRule(input: {branchProtectionRuleId: \"BPR_x\", requiresStatusChecks: false}) { clientMutationId } }'"
expect_deny "gh api graphql -f query='mutation { deleteBranchProtectionRule(input: {branchProtectionRuleId: \"BPR_x\"}) { clientMutationId } }'"

# curl / wget vers api.github.com (REST ou GraphQL, avec le token du board)
expect_deny 'curl -s -X PUT -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/repos/EnO33/vigie/pulls/12/merge'
expect_deny 'curl -fsSL -H "Authorization: bearer $GH_TOKEN" -d @q.json https://api.github.com/graphql'
expect_deny 'wget -qO- --header="Authorization: Bearer $GH_TOKEN" https://api.github.com/repos/EnO33/vigie/rulesets'

# Règles historiques, contournées avant par des espaces doubles
expect_deny 'gh  pr merge 12 --squash'
expect_deny 'gh pr  review 12  --approve'
expect_deny 'gh  issue  edit 3 --add-label  board'

# Témoins : ce qui doit rester permis
expect_allow 'gh api repos/{owner}/{repo}/issues/12 --jq .id'
expect_allow 'gh api -X POST repos/{owner}/{repo}/issues/3/sub_issues -F sub_issue_id=42'
expect_allow 'gh api repos/{owner}/{repo}/pulls/12/files --jq ".[].filename"'
expect_allow 'gh pr view 12 --json mergeable,mergeStateStatus'
expect_allow 'grep -rn "statuses" factory/'
expect_allow "gh api graphql -f query='{ repository(owner: \"EnO33\", name: \"vigie\") { pullRequest(number: 12) { mergeable } } }'"
expect_allow 'grep -rn mergePullRequest factory/'
expect_allow "curl -fsSL https://crates.io/api/v1/crates/serde/versions | jq -r '.versions[0].num'"
# Hors agent de la factory (session du board), le hook ne bloque rien.
expect_allow 'gh api -X PUT repos/{owner}/{repo}/pulls/12/merge' 0

echo
if [ "$failures" -eq 0 ]; then echo "✓ guard.sh : tous les tests passent"
else echo "✗ guard.sh : $failures échec(s)"; exit 1; fi
