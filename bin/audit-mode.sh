#!/usr/bin/env bash
# Usage: audit-mode.sh on|off|status
# Marks the calling Claude session as read-only audit for hooks/guard.sh. Marker file =
# ${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/audit/<pid>, pid = AGENT_LOCK_PID (default $PPID):
# call as `AGENT_LOCK_PID=$PPID audit-mode.sh on`. Markers of dead pids are ignored and pruned.
base=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/audit
pid=${AGENT_LOCK_PID:-$PPID}
case ${1:-} in
  on)
    mkdir -p "$base"
    for f in "$base"/*; do
      [ -e "$f" ] && ! kill -0 "${f##*/}" 2>/dev/null && rm -f "$f"
    done
    : > "$base/$pid" ;;
  off) rm -f "$base/$pid" ;;
  status) if [ -f "$base/$pid" ]; then echo on; else echo off; exit 1; fi ;;
  *) echo "usage: $0 on|off|status" >&2; exit 2 ;;
esac
