#!/usr/bin/env bash
# Usage: install.sh [--home DIR]  (default $HOME). Idempotent.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd -P)"
DEST="$HOME"; CUSTOM=0
if [ "${1:-}" = "--home" ]; then DEST="${2:?--home needs a dir}"; CUSTOM=1; fi
C="$DEST/.claude"
mkdir -p "$C/skills" "$C/agents"

for d in "$REPO"/skills/*/; do
  n=$(basename "$d")
  [ "$n" = _shared ] && n=_agent-workflow-shared
  ln -sfn "${d%/}" "$C/skills/$n"
done
for f in "$REPO"/agents/*.md; do
  [ -e "$f" ] && ln -sfn "$f" "$C/agents/$(basename "$f")"
done

S="$C/settings.json"
[ -f "$S" ] || echo '{}' > "$S"
[ -e "$S.bak-agent-workflow" ] || cp "$S" "$S.bak-agent-workflow"  # keep the first original
tmp=$(mktemp)
jq --arg cmd "\"$REPO/hooks/guard.sh\"" '
  .hooks.PreToolUse = ((.hooks.PreToolUse // [])
    | if any(.[]; (.hooks // [])[]?.command | tostring | test("/guard\\.sh\"?$")) then .
      else . + [{matcher:"Bash|Edit|Write|MultiEdit|mcp__claude_ai_Atlassian__transitionJiraIssue",
                 hooks:[{type:"command",command:$cmd}]}] end)' "$S" > "$tmp"
mv "$tmp" "$S"

P="$REPO/launchd/com.agentworkflow.housekeeping.plist"
if [ -f "$P" ]; then
  out="$DEST/Library/LaunchAgents/$(basename "$P")"
  mkdir -p "$(dirname "$out")" "$DEST/.agent-workflow/logs"
  sed -e "s|__AGENT_WORKFLOW_DIR__|$REPO|g" -e "s|__HOME__|$DEST|g" "$P" > "$out"
  if [ "$CUSTOM" = 0 ]; then
    launchctl bootout "gui/$(id -u)" "$out" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$out"
  fi
fi
echo "installed into $DEST"
