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

# review fixes: remote/fetch/reflog writes, gh/glab allowlist
check 2 'git remote -v add evil https://x'
check 2 'git remote --verbose remove origin'
check 0 'git remote -v show origin'
check 2 'git fetch . HEAD:refs/heads/newbr'
check 2 'git fetch origin +x:main'
check 2 'git reflog expire --expire=now --all'
check 2 'git reflog delete HEAD@{0}'
check 0 'git reflog -n 5'
check 2 'gh api repos/o/r/issues -fbody=hi'
check 2 'gh api repos/o/r/issues -Ftitle=hi'
check 2 'gh issue develop 12'
check 2 'gh repo delete o/r --yes'
check 2 'gh workflow run ci.yml'
check 2 'glab mr update 3 --title x'
check 2 'gh secret set X'
check 0 'gh run list'
check 0 'glab mr view 3'
check 0 'gh search issues foo'
check 0 'gh auth status'

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

# agent teams: the audit SPV's guard records its session; teammates (--parent-session-id) inherit audit
: > "$T/st/audit/$$"
run "$(jq -cn --arg d "$W" '{tool_name:"Bash",tool_input:{command:"git log"},cwd:$d,session_id:"S2"}')" >/dev/null
assert_eq "$$" "$(cat "$T/st/audit/session-S2" 2>/dev/null)" "SPV guard records session -> pid"
rm "$T/st/audit/$$"
sleep 60 & SP=$!; disown "$SP"; : > "$T/st/audit/$SP"; echo "$SP" > "$T/st/audit/session-S1"
mate() { bash -c 'printf "%s" "$1" | "$2" >/dev/null 2>&1; echo $?' _ "$(jq -cn --arg d "$W" '{tool_name:"Bash",tool_input:{command:"git commit -m x"},cwd:$d}')" "$G" --parent-session-id "$1"; }
assert_eq 2 "$(mate S1)" "[2] teammate of audit SPV: git commit"
assert_eq 0 "$(mate S9)" "[0] teammate of other session"
rm "$T/st/audit/$SP"
assert_eq 0 "$(mate S1)" "[0] teammate after SPV audit off"
kill "$SP" 2>/dev/null

# normal mode unchanged
tool_check 0 Write "$(jq -cn --arg p "$W/a.txt" '{file_path:$p}')" AGENT_AUDIT=
tool_check 0 mcp__claude_ai_Atlassian__addCommentToJiraIssue '{"issueIdOrKey":"PROJ-1"}' AGENT_AUDIT=
assert_eq 0 "$(run "$(jq -cn --arg d "$W" '{tool_name:"Bash",tool_input:{command:"git commit -m x"},cwd:$d}')")" "[0] normal: git commit"
exit $FAILS
