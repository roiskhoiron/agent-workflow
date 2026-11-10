#!/usr/bin/env bash
# Usage: device-preempt.sh info <res>              -> "owner=<o> since=<n>m testing=yes|no" (exit 1 if free)
#        device-preempt.sh take <res> <new-owner>  -> user chose to take <res> over: stop the holder's test
#                                                     processes for that device, leave a note, move the lock
# take exit: 0 lock is ours; 1 lock went to someone else meanwhile; 2 usage.
# Holder human-* is never interrupted (note + move only). Tests are stopped (INT, TERM, KILL), not frozen.
# Note: ${AGENT_WORKFLOW_STATE}/preempted/device-<old holder pid>, line "<res>\t<new owner>\t<YYYY-MM-DD HH:MM>"
# Env: AGENT_LOCK_PID, AGENT_LOCK_DIR (see device-lock.sh); AGENT_WORKFLOW_STATE; PREEMPT_TIMEOUT (s, default 30)
# shortcut: tree/gone/wait_gone copied from build-preempt.sh; dedupe if a third script needs them
cmd=$1 res=$2 new=$3
LOCK="$(dirname "$0")/device-lock.sh"
D="${AGENT_LOCK_DIR:-$HOME/.agent-workflow/locks}/$(printf '%s' "$res" | sed 's/%/%25/g; s#/#%2F#g; s/:/%3A/g')"
NOTES="${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/preempted"
TEST='maestro|am instrument|xcodebuild.*test|ios-ui\.sh'
export AGENT_LOCK_PID=${AGENT_LOCK_PID:-$PPID}
usage() { echo "usage: $0 info <res> | take <res> <new-owner>" >&2; exit 2; }
[ -n "$res" ] || usage

tree() { local c; for c in $(pgrep -P "$1"); do echo "$c"; tree "$c"; done; }
matching() { # holder pid -> its descendants running a test command that mentions this device id
  local p; for p in $(tree "$1"); do
    ps -o command= -p "$p" 2>/dev/null | grep -iE "$TEST" | grep -qF -- "${res#*:}" && echo "$p"
  done; }
gone() { local p; for p in $1; do kill -0 "$p" 2>/dev/null && return 1; done; return 0; }
wait_gone() { local i; for ((i = 0; i < ${PREEMPT_TIMEOUT:-30} * 5; i++)); do gone "$1" && return 0; sleep 0.2; done; return 1; }

case $cmd in
  info)
    o=$("$LOCK" who "$res"); [ -n "$o" ] || exit 1
    since=$(( ($(date +%s) - $(stat -f %m "$D" 2>/dev/null || date +%s)) / 60 ))
    t=no; [ -n "$(matching "$(cat "$D/pid" 2>/dev/null)")" ] && t=yes
    echo "owner=$o since=${since}m testing=$t" ;;
  take)
    [ -n "$new" ] || usage
    "$LOCK" acquire "$res" "$new" >/dev/null && exit 0
    old=$("$LOCK" who "$res") oldpid=$(cat "$D/pid" 2>/dev/null)
    case $old in human-*) ;; *)
      pids=$(matching "$oldpid")
      if [ -n "$pids" ]; then
        kill -INT $pids 2>/dev/null
        wait_gone "$pids" || { kill -TERM $pids 2>/dev/null; wait_gone "$pids" || kill -KILL $pids 2>/dev/null; }
      fi ;;
    esac
    if [ -n "$oldpid" ]; then
      f="$NOTES/device-$oldpid"; mkdir -p "$NOTES"
      { grep -vF "$res$(printf '\t')" "$f" 2>/dev/null
        printf '%s\t%s\t%s\n' "$res" "$new" "$(date '+%Y-%m-%d %H:%M')"; } > "$f.tmp" && mv "$f.tmp" "$f"
    fi
    "$LOCK" move "$res" "$old" "$new" >/dev/null || { echo "kunci keburu diambil $("$LOCK" who "$res")" >&2; exit 1; } ;;
  *) usage ;;
esac
