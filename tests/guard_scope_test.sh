#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
G="$REPO/hooks/guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
M="$T/main"; L="$T/linked"
git init -q "$M"; git -C "$M" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
# main checkout without linked worktree: editable
assert_eq 0 "$(printf '%s' "$(jq -cn --arg p "$M/a.txt" --arg c "$M" '{tool_name:"Edit",tool_input:{file_path:$p},cwd:$c}')" | "$G" 2>/dev/null >/dev/null; echo $?)" "[0] main without linked worktree"
git -C "$M" worktree add -q -b feat/x "$L"
mkdir -p "$T/plain" "$T/st"
cat > "$T/st/jira-transitions.json" <<'J'
{"PROJ":{"allow":["21","31"],"names":{"21":"In Progress","31":"Ready To Review"}},"AB2":{"allow":["21"]}}
J
export AGENT_WORKFLOW_STATE="$T/st"

run() { printf '%s' "$1" | "$G" 2>"$T/err" >/dev/null; echo $?; }
file_check() { # expected tool path
  local j; j=$(jq -cn --arg t "$2" --arg p "$3" --arg c "$M" '{tool_name:$t,tool_input:{file_path:$p},cwd:$c}')
  assert_eq "$1" "$(run "$j")" "[$1] $2 $3"
}
jira() { # expected key transition-json
  local j; j=$(jq -cn --arg k "$2" --argjson t "$3" '{tool_name:"mcp__claude_ai_Atlassian__transitionJiraIssue",tool_input:{cloudId:"c",issueIdOrKey:$k,transition:$t},cwd:"/"}')
  assert_eq "$1" "$(run "$j")" "[$1] jira $2 $3"
}

for t in Edit Write MultiEdit; do
  file_check 2 $t "$M/a.txt"
  file_check 2 $t "$M/new/dir/a.txt"
  file_check 0 $t "$L/a.txt"
  file_check 0 $t "$L/new/dir/a.txt"
  file_check 0 $t "$T/plain/a.txt"
done
file_check 2 Edit "$T/main/../main/a.txt"
ln -s "$M" "$T/sym"; file_check 2 Edit "$T/sym/a.txt"
assert_eq 0 "$(run "$(jq -cn --arg c "sed -i s/a/b/ $M/a.txt" --arg d "$M" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')")" "[0] bash sed -i not checked"

jira 0 PROJ-5 '{"id":"21"}'
jira 0 PROJ-5 '{"id":21}'
jira 0 AB2-15 '{"id":"21"}'
jira 2 PROJ-5 '{"id":"41"}'; grep -q "Done hanya dipindah kolega" "$T/err"; assert_eq 0 $? "msg Done"
jira 2 AB2-15 '{"id":"31"}'
jira 2 NOPE-1 '{"id":"21"}'; grep -q "jalankan setup transisi" "$T/err"; assert_eq 0 $? "msg setup"
jira 2 PROJ-5 '{}'
echo 'bukan json' > "$T/st/jira-transitions.json"
jira 2 PROJ-5 '{"id":"21"}'; grep -q "jalankan setup transisi" "$T/err"; assert_eq 0 $? "invalid config msg"
rm "$T/st/jira-transitions.json"
jira 2 PROJ-5 '{"id":"21"}'
exit $((FAILS>0))
