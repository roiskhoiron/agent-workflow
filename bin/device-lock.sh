#!/usr/bin/env bash
# Usage: device-lock.sh acquire|release|who <resource> [owner]
# Locks live in ${AGENT_LOCK_DIR:-$HOME/.agent-workflow/locks} (mkdir-atomic, files pid+owner).
# The recorded pid is AGENT_LOCK_PID (default $PPID): set it to the caller's long-lived
# process; the lock counts as free once that pid is dead (kill -0).
cmd=$1 res=$2 owner=$3
base=${AGENT_LOCK_DIR:-$HOME/.agent-workflow/locks}
# percent-encode %, / and : so distinct resources never share a dir
d="$base/$(printf '%s' "$res" | sed 's/%/%25/g; s#/#%2F#g; s/:/%3A/g')"
cur() { cat "$d/owner" 2>/dev/null; }
case $cmd in
  acquire)
    mkdir -p "$base"
    for _ in 1 2; do
      if mkdir "$d" 2>/dev/null; then
        echo "${AGENT_LOCK_PID:-$PPID}" > "$d/pid"; echo "$owner" > "$d/owner"; exit 0
      fi
      if [ "$(cur)" = "$owner" ]; then echo "${AGENT_LOCK_PID:-$PPID}" > "$d/pid"; exit 0; fi
      pid=$(cat "$d/pid" 2>/dev/null)
      # empty pid = holder mid-acquire (or crashed): held only while the dir is <10s old
      if [ -z "$pid" ]; then
        [ $(( $(date +%s) - $(stat -f %m "$d" 2>/dev/null || echo 0) )) -lt 10 ] && { cur; exit 1; }
      elif kill -0 "$pid" 2>/dev/null; then cur; exit 1; fi
      rm -rf "$d"   # stale: reclaim (small race between two reclaimers accepted)
    done
    cur; exit 1 ;;
  release) [ "$(cur)" = "$owner" ] && rm -rf "$d"; exit 0 ;;
  who) cur ;;
  *) echo "usage: $0 acquire|release|who <resource> [owner]" >&2; exit 2 ;;
esac
