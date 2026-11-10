#!/usr/bin/env bash
# Usage: uat-watch.sh <resource> <app> <owner> <outdir>
# Follows the app's log while a human tests on a physical phone (UAT slot, owner human-<KODE>);
# every line -> <outdir>/uat-log.txt, crash lines also -> uat-crash.txt. Ends when the lock owner
# changes (end=released, lock untouched) or no log line arrives for UAT_IDLE_SEC (default 180):
# then releases the lock (end=idle). Prints "end=idle|released crash=<n> log=<outdir>/uat-log.txt".
# <app> = Android package or iOS process name (CFBundleExecutable); resource android:<serial> | ios:<udid>.
# Env: UAT_LOG_CMD (sh -c string replacing the default log command, for tests), UAT_IDLE_SEC,
#      ADB (default adb), PMD3 (default pymobiledevice3); AGENT_LOCK_DIR/AGENT_LOCK_PID (see device-lock.sh).
# Android default path with the package not found (not installed / device offline): prints
# "end=error reason=<alasan> log=...", exit 3, lock untouched.
# Exit: 0 after an end=idle|released line; 3 error; 2 usage.
# shortcut: idle uses whole-second $SECONDS (fires >UAT_IDLE_SEC); checks run at most once per second.
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
  [ -n "$uid" ] || { echo "end=error reason=paket $app tidak ditemukan di $id (belum terpasang atau device offline) log=$log"; exit 3; }
  cmd="'$ADB' -s '$id' logcat -T 1 -v threadtime --uid=$uid"
else cmd="'$PMD3' syslog live --udid '$id' -pn '$app'"; fi

fifo=$(mktemp -u "${TMPDIR:-/tmp}/uat-watch.XXXXXX"); mkfifo "$fifo"
sh -c "$cmd" > "$fifo" 2>&1 & lp=$!
exec 3< "$fifo"; rm -f "$fifo"
trap 'c=$(pgrep -P $lp); kill $lp $c 2>/dev/null; wait $lp 2>/dev/null' EXIT
exec 4>> "$log" 5>> "$crash"

n=0 end= last=$SECONDS chk=$SECONDS
while :; do
  tick=
  if IFS= read -r -t 1 line <&3; then
    printf '%s\n' "$line" >&4; last=$SECONDS
    case $line in
      *"FATAL EXCEPTION"*|*"ANR in"*|*"Fatal signal"*|*"Terminating app due to"*|*EXC_BAD*|*SIGABRT*|*"Fatal error"*)
        printf '%s\n' "$line" >&5; n=$((n+1)) ;;
    esac
  else
    kill -0 $lp 2>/dev/null || sleep 1 # EOF (log process died): don't spin, wait out the idle timer
    tick=1
  fi
  [ -n "$tick" ] || [ $SECONDS -ne $chk ] || continue
  chk=$SECONDS
  [ "$("$LOCK" who "$res")" = "$owner" ] || { end=released; break; }
  [ $(( SECONDS - last )) -gt "${UAT_IDLE_SEC:-180}" ] && { "$LOCK" release "$res" "$owner"; end=idle; break; }
done
echo "end=$end crash=$n log=$log"
