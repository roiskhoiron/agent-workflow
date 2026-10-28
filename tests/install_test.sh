source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
H=$(mktemp -d); trap 'rm -rf "$H"' EXIT
mkdir -p "$H/.claude"
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}' > "$H/.claude/settings.json"

assert_exit 0 "install run 1" -- bash "$REPO/install.sh" --home "$H"
assert_exit 0 "install run 2 (idempotent)" -- bash "$REPO/install.sh" --home "$H"

S="$H/.claude/settings.json"
assert_eq "yes" "$([ -L "$H/.claude/skills/validate-tiket" ] && echo yes || echo no)" "skill symlink"
assert_eq "yes" "$([ -L "$H/.claude/skills/_agent-workflow-shared" ] && echo yes || echo no)" "shared symlink"
assert_eq "no" "$([ -e "$H/.claude/skills/_shared" ] && echo yes || echo no)" "_shared not linked by own name"
assert_eq "1" "$(jq '[.hooks.PreToolUse[]|select(.hooks[0].command|test("guard.sh"))]|length' "$S")" "guard hook once"
assert_eq "1" "$(jq '[.hooks.PreToolUse[]|select(.hooks[0].command=="rtk hook claude")]|length' "$S")" "rtk hook preserved"
assert_eq "\"$REPO/hooks/guard.sh\"" "$(jq -r '.hooks.PreToolUse[]|select(.hooks[0].command|test("guard.sh"))|.hooks[0].command' "$S")" "guard path quoted, from repo location"
assert_eq "yes" "$([ -f "$S.bak-agent-workflow" ] && echo yes || echo no)" "backup made"
assert_eq "0" "$(jq '[.hooks.PreToolUse[]|select(.hooks[0].command|test("guard.sh"))]|length' "$S.bak-agent-workflow")" "second install keeps first (original) backup"

# repo path with a space: hook command runs through a shell
R="$H/my repo"; mkdir -p "$R"; cp -R "$REPO/install.sh" "$REPO/hooks" "$REPO/skills" "$REPO/agents" "$R/"
H2="$H/home2"; mkdir -p "$H2"
assert_exit 0 "install from path with space" -- bash "$R/install.sh" --home "$H2"
assert_exit 0 "install from path with space, run 2" -- bash "$R/install.sh" --home "$H2"
assert_eq "1" "$(jq '[.hooks.PreToolUse[]|select(.hooks[0].command|test("guard.sh"))]|length' "$H2/.claude/settings.json")" "space path: guard hook once"
c=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$H2/.claude/settings.json")
assert_eq 0 "$(echo '{"tool_name":"Read"}' | sh -c "$c" >/dev/null 2>&1; echo $?)" "space path: hook command runs via shell"
assert_eq "yes" "$([ -d "$H/.agent-workflow/logs" ] && echo yes || echo no)" "logs dir created for launchd plist"
assert_eq "1" "$(grep -c '^# Jira agent workflow' "$H/.claude/CLAUDE.md")" "global CLAUDE.md section appended once"
exit $FAILS
