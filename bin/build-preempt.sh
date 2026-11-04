#!/usr/bin/env bash
# Usage: build-preempt.sh info              -> "owner=<o> since=<n>m uploading=yes|no" (exit 1 if free)
#        build-preempt.sh take <new-owner>  -> user chose to put <new-owner> first: stop the holder's
#                                              build, move build:heavy to <new-owner>, leave a note
#        build-preempt.sh check <owner>     -> was <owner> preempted? prints the note once (exit 0), else 1
# take exit: 0 lock is ours; 1 lock went to someone else meanwhile; 3 holder is uploading (never
# interrupted: wait instead); 2 usage. Builds are stopped, not frozen (frozen builds keep their RAM).
# Env: AGENT_LOCK_PID, AGENT_LOCK_DIR (see device-lock.sh); AGENT_WORKFLOW_STATE; PREEMPT_TIMEOUT (s, default 30)
cmd=$1 arg=$2
LOCK="$(dirname "$0")/device-lock.sh" RES=build:heavy
D="${AGENT_LOCK_DIR:-$HOME/.agent-workflow/locks}/build%3Aheavy"
NOTES="${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/preempted"
BUILD='xcodebuild|gradle' UPLOAD='firebase|appdistribution|altool|notarytool'
export AGENT_LOCK_PID=${AGENT_LOCK_PID:-$PPID}
usage() { echo "usage: $0 info | take <new-owner> | check <owner>" >&2; exit 2; }

tree() { local c; for c in $(pgrep -P "$1"); do echo "$c"; tree "$c"; done; }
matching() { # pattern -> pids under the holder's session whose command matches
  local p; for p in $(tree "$(cat "$D/pid" 2>/dev/null)"); do
    ps -o command= -p "$p" 2>/dev/null | grep -qE "$1" && echo "$p"
  done; }
gone() { local p; for p in $1; do kill -0 "$p" 2>/dev/null && return 1; done; return 0; }
wait_gone() { local i; for ((i = 0; i < ${PREEMPT_TIMEOUT:-30} * 5; i++)); do gone "$1" && return 0; sleep 0.2; done; return 1; }

case $cmd in
  info)
    o=$("$LOCK" who "$RES"); [ -n "$o" ] || exit 1
    since=$(( ($(date +%s) - $(stat -f %m "$D" 2>/dev/null || date +%s)) / 60 ))
    up=no; [ -n "$(matching "$UPLOAD")" ] && up=yes
    echo "owner=$o since=${since}m uploading=$up" ;;
  take)
    [ -n "$arg" ] || usage
    "$LOCK" acquire "$RES" "$arg" >/dev/null && exit 0
    old=$("$LOCK" who "$RES")
    [ -n "$(matching "$UPLOAD")" ] && { echo "$old sedang upload; tunggu sampai selesai" >&2; exit 3; }
    pids=$(matching "$BUILD")
    if [ -n "$pids" ]; then
      kill -INT $pids 2>/dev/null   # xcodebuild/gradle cancel cleanly on SIGINT
      wait_gone "$pids" || { kill -TERM $pids 2>/dev/null; wait_gone "$pids" || kill -KILL $pids 2>/dev/null; }
    fi
    mkdir -p "$NOTES" && echo "didahulukan oleh $arg pada $(date '+%Y-%m-%d %H:%M')" > "$NOTES/$old"
    "$LOCK" release "$RES" "$old"
    "$LOCK" acquire "$RES" "$arg" >/dev/null || { echo "kunci keburu diambil $("$LOCK" who "$RES")" >&2; exit 1; } ;;
  check)
    [ -n "$arg" ] || usage
    [ -f "$NOTES/$arg" ] || exit 1
    cat "$NOTES/$arg"; rm -f "$NOTES/$arg" ;;
  *) usage ;;
esac
