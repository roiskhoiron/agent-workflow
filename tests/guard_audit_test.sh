#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
G="$REPO/hooks/guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
W="$T/work"
git init -q "$W"
export AGENT_WORKFLOW_STATE="$T/st"; mkdir -p "$T/st"

run() { printf '%s' "$1" | "$G" >/dev/null 2>&1; echo $?; }
check() { # expected-exit command   (audit via env)
  assert_eq "$1" "$(AGENT_AUDIT=1 run "$(jq -cn --arg c "$2" --arg d "$W" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')")" "[$1] audit: $2"
}
tool_check() { # expected-exit tool tool_input-json [env]
  assert_eq "$1" "$(env ${4:-AGENT_AUDIT=1} bash -c 'printf "%s" "$1" | "$2" >/dev/null 2>&1; echo $?' _ "$(jq -cn --arg t "$2" --argjson i "$3" --arg d "$W" '{tool_name:$t,tool_input:$i,cwd:$d}')" "$G")" "[$1] ${4:-audit}: $2 $3"
}

# git: read allowed, write blocked
check 2 'git commit -m x'
check 2 'git checkout -b x'
check 2 'git stash'
check 2 'git add .'
check 2 'git branch feat/x'
check 2 'git tag v1.0.0'
check 2 'git worktree add ../w-1'
check 2 'git config user.name x'
check 0 'git log --oneline -5'
check 0 'git -C /x show HEAD:a.txt'
check 0 'git --no-pager blame a.txt'
check 0 'git fetch origin --tags'
check 0 'git branch -a'
check 0 'git tag -l'
check 0 'git remote -v'
check 0 'git worktree list'
check 0 'git grep foo v1.2.3'

# forges and orca
check 2 'gh pr create --title x'
check 2 'glab mr note 1 -m x'
check 2 'gh api -X POST repos/a/b/issues'
check 0 'gh pr view 1'
check 0 'gh api repos/a/b/pulls'
check 2 'orca worktree create --name x'

# files: only the audit work folder
tool_check 2 Write "$(jq -cn --arg p "$W/a.txt" '{file_path:$p}')"
tool_check 0 Write '{"file_path":"/tmp/audit/s1/temuan.md"}'
tool_check 0 Write "$(jq -cn --arg p "${TMPDIR:-/tmp/}audit/s1/a.md" '{file_path:$p}')"
tool_check 2 NotebookEdit "$(jq -cn --arg p "$W/n.ipynb" '{notebook_path:$p}')"

# Jira/Confluence writes blocked, reads allowed
for t in addCommentToJiraIssue createJiraIssue editJiraIssue transitionJiraIssue; do
  tool_check 2 "mcp__claude_ai_Atlassian__$t" '{"issueIdOrKey":"PROJ-1"}'
done
tool_check 0 mcp__claude_ai_Atlassian__getJiraIssue '{"issueIdOrKey":"PROJ-1"}'
tool_check 0 mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql '{"jql":"x"}'

# marker file for an ancestor pid (this test shell) turns audit on without env
mkdir -p "$T/st/audit"; : > "$T/st/audit/$$"
assert_eq 2 "$(run "$(jq -cn --arg d "$W" '{tool_name:"Bash",tool_input:{command:"git commit -m x"},cwd:$d}')")" "[2] marker: git commit"
rm "$T/st/audit/$$"; : > "$T/st/audit/999999"
assert_eq 0 "$(run "$(jq -cn --arg d "$W" '{tool_name:"Bash",tool_input:{command:"git commit -m x"},cwd:$d}')")" "[0] dead-pid marker ignored"

# normal mode unchanged
tool_check 0 Write "$(jq -cn --arg p "$W/a.txt" '{file_path:$p}')" AGENT_AUDIT=
tool_check 0 mcp__claude_ai_Atlassian__addCommentToJiraIssue '{"issueIdOrKey":"PROJ-1"}' AGENT_AUDIT=
assert_eq 0 "$(run "$(jq -cn --arg d "$W" '{tool_name:"Bash",tool_input:{command:"git commit -m x"},cwd:$d}')")" "[0] normal: git commit"
exit $FAILS
