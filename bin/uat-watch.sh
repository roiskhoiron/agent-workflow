#!/usr/bin/env bash
# Usage: uat-watch.sh <resource> <app> <owner> <outdir>
# Follows the app's log while a human tests on a physical phone (UAT slot, owner human-<KODE>);
# every line -> <outdir>/uat-log.txt, crash lines also -> uat-crash.txt. Ends when the lock owner
# changes (end=released, lock untouched) or no log line arrives for UAT_IDLE_SEC (default 180):
# then releases the lock (end=idle). Prints "end=idle|released crash=<n> log=<outdir>/uat-log.txt".
# <app> = Android package or iOS process name (CFBundleExecutable); resource android:<serial> | ios:<udid>.
# Env: UAT_LOG_CMD (sh -c string replacing the default log command, for tests), UAT_IDLE_SEC,
#      ADB (default adb), PMD3 (default pymobiledevice3); AGENT_LOCK_DIR/AGENT_LOCK_PID (see device-lock.sh).
# Exit: 0 always after the end line; 2 usage.
# shortcut: ANRs logged by system_server (another uid) are missed by --uid; upgrade to full logcat + pid filter if ANRs slip through.
res=$1 app=$2 owner=$3 out=$4
[ $# -eq 4 ] || { echo "usage: $0 <resource> <app> <owner> <outdir>" >&2; exit 2; }
LOCK="$(dirname "$0")/device-lock.sh" ADB=${ADB:-adb} PMD3=${PMD3:-pymobiledevice3}
id=${res#*:}
mkdir -p "$out" || exit 2
log="$out/uat-log.txt" crash="$out/uat-crash.txt"; : > "$log"; : > "$crash"

if [ -n "$UAT_LOG_CMD" ]; then cmd=$UAT_LOG_CMD
elif [ "${res%%:*}" = android ]; then
  uid=$("$ADB" -s "$id" shell pm list packages -U "$app" | sed -n "s/^package:$app uid:\([0-9]*\).*/\1/p" | head -1)
  cmd="'$ADB' -s '$id' logcat -T 1 -v threadtime --uid=$uid"
else cmd="'$PMD3' syslog live --udid '$id' -pn '$app'"; fi

fifo=$(mktemp -u "${TMPDIR:-/tmp}/uat-watch.XXXXXX"); mkfifo "$fifo"
sh -c "$cmd" > "$fifo" 2>&1 & lp=$!
exec 3< "$fifo"; rm -f "$fifo"
trap 'pkill -P $lp 2>/dev/null; kill $lp 2>/dev/null' EXIT

n=0 end= last=$(date +%s)
while :; do
  if IFS= read -r -t 1 line <&3; then
    printf '%s\n' "$line" >> "$log"; last=$(date +%s)
    if printf '%s\n' "$line" | grep -qE 'FATAL EXCEPTION|ANR in|Fatal signal|Terminating app due to|EXC_BAD|SIGABRT|Fatal error'; then
      printf '%s\n' "$line" >> "$crash"; n=$((n+1))
    fi
  else
    [ $? -gt 128 ] || sleep 1 # EOF (log process died): don't spin, wait out the idle timer
  fi
  [ "$("$LOCK" who "$res")" = "$owner" ] || { end=released; break; }
  [ $(( $(date +%s) - last )) -ge "${UAT_IDLE_SEC:-180}" ] && { "$LOCK" release "$res" "$owner"; end=idle; break; }
done
echo "end=$end crash=$n log=$log"
