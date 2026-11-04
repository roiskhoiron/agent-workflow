#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
A="$REPO/bin/audit-mode.sh"
export AGENT_WORKFLOW_STATE=$(mktemp -d); trap 'rm -rf "$AGENT_WORKFLOW_STATE"' EXIT
M="$AGENT_WORKFLOW_STATE/audit"

AGENT_LOCK_PID=$$ "$A" on
assert_eq yes "$([ -f "$M/$$" ] && echo yes || echo no)" "on creates marker for pid"
assert_eq on "$(AGENT_LOCK_PID=$$ "$A" status)" "status prints on"
assert_exit 0 "status exit 0 when on" -- env AGENT_LOCK_PID=$$ "$A" status
AGENT_LOCK_PID=$$ "$A" off
assert_eq no "$([ -f "$M/$$" ] && echo yes || echo no)" "off removes marker"
assert_eq off "$(AGENT_LOCK_PID=$$ "$A" status)" "status prints off"
assert_exit 1 "status exit 1 when off" -- env AGENT_LOCK_PID=$$ "$A" status
touch "$M/999999"; echo 999999 > "$M/session-dead"; echo $$ > "$M/session-live"
AGENT_LOCK_PID=$$ "$A" on
assert_eq no "$([ -f "$M/999999" ] && echo yes || echo no)" "on prunes marker of dead pid"
assert_eq no "$([ -f "$M/session-dead" ] && echo yes || echo no)" "on prunes session of dead pid"
assert_eq yes "$([ -f "$M/session-live" ] && echo yes || echo no)" "on keeps session of live pid"
assert_exit 2 "bad argument exits 2" -- "$A" nope
exit $FAILS
