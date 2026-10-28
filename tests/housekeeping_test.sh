#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
H="$REPO/bin/housekeeping.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export AGENT_LOCK_DIR="$T/locks" HK_BUSY=0 HK_FREE_GB=200
export HK_NOTIFY="$T/notify.sh"
printf '#!/bin/sh\necho "$1" >> "%s/notified"\n' "$T" > "$T/notify.sh"; chmod +x "$T/notify.sh"
CALLS="$T/calls"
for n in xcrun pod brew npm; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$n" "$CALLS" > "$T/$n"; chmod +x "$T/$n"
done
export XCRUN="$T/xcrun" POD="$T/pod" BREW="$T/brew" NPM="$T/npm"
OLD=202001010000
D="$HOME/Library/Developer/Xcode/DerivedData"; G="$HOME/.gradle"; K="$HOME/.konan"; DS="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
S="$HOME/.agent-workflow/state"; LOG="$HOME/.agent-workflow/logs/housekeeping.log"
ts() { date -j -f '%Y-%m-%d %H:%M' "$1" +%s; }   # local time -> epoch
mk() { mkdir -p "$(dirname "$1")"; : > "$1"; [ -n "${2:-}" ] && touch -t "$2" "$1"; return 0; }
reset() {
  rm -rf "$HOME" "$T/notified" "$CALLS" "$T/locks"; mkdir -p "$HOME"
  mkdir -p "$D/old" "$D/new" "$G/caches/build-cache-1/o" "$G/caches/build-cache-1/n" "$K/cache-1/old" "$K/cache-1/new" "$DS/old" "$DS/new"
  touch -t $OLD "$K/cache-1/old" "$D/old" "$G/caches/build-cache-1/o" "$DS/old"
  mk "$G/daemon/8/x.log" $OLD
  mkdir -p "$HOME/proj/app/build/out"; mk "$HOME/proj/app/build/out/a.apk" $OLD; mk "$HOME/proj/app/build/out/new.aab"
  mk "$HOME/proj/app/src/keep.apk" $OLD
  mkdir -p "$HOME/.agent-workflow"; echo "$HOME/proj" > "$HOME/.agent-workflow/build-roots.txt"
}
run() { HK_NOW=$(ts "$1") bash "$H"; }

# --- daily 02:00 nothing
reset; run "2026-10-28 02:00"
assert_eq yes "$([ -d "$D/old" ] && echo yes)" "02:00 no daily"
# --- daily 03:10 (Wednesday)
reset; run "2026-10-28 03:10"
assert_eq "" "$([ -d "$D/old" ] && echo yes)" "daily removes old DerivedData"
assert_eq yes "$([ -d "$D/new" ] && echo yes)" "daily keeps new DerivedData"
assert_eq "" "$([ -e "$HOME/proj/app/build/out/a.apk" ] && echo yes)" "daily removes old apk"
assert_eq yes "$([ -e "$HOME/proj/app/build/out/new.aab" ] && echo yes)" "keeps new aab"
assert_eq yes "$([ -e "$HOME/proj/app/src/keep.apk" ] && echo yes)" "apk outside build/ kept"
assert_eq yes "$([ -d "$G/caches/build-cache-1/o" ] && echo yes)" "daily leaves gradle"
assert_eq yes "$([ -f "$S/daily" ] && echo yes)" "daily stamp"
assert_eq "" "$([ -e "$CALLS" ] && echo yes)" "daily runs no external tools"
touch -t $OLD "$D/new"; run "2026-10-28 04:00"
assert_eq yes "$([ -d "$D/new" ] && echo yes)" "daily only once per day"
run "2026-10-29 03:00"
assert_eq "" "$([ -d "$D/new" ] && echo yes)" "daily next day runs"
# --- busy
reset; HK_BUSY=1 run "2026-10-28 03:10"
assert_eq yes "$([ -d "$D/old" ] && echo yes)" "busy: nothing deleted"
assert_eq "" "$([ -e "$S/daily" ] && echo yes)" "busy: no stamp"
reset; mkdir -p "$T/locks/x"; run "2026-10-28 03:10"
assert_eq yes "$([ -d "$D/old" ] && echo yes)" "lock dir present = busy"
reset; mkdir -p "$T/locks/x"; echo $$ > "$T/locks/x/pid"; run "2026-10-28 03:10"
assert_eq yes "$([ -d "$D/old" ] && echo yes)" "lock with live pid = busy"
reset; mkdir -p "$T/locks/x"; sh -c 'echo $$' > "$T/locks/x/pid"; run "2026-10-28 03:10"
assert_eq "" "$([ -d "$D/old" ] && echo yes)" "stale lock (dead pid) ignored, cleanup runs"
reset; mkdir -p "$T/locks/x"; touch -t $OLD "$T/locks/x"; run "2026-10-28 03:10"
assert_eq "" "$([ -d "$D/old" ] && echo yes)" "old lock without pid ignored, cleanup runs"
# --- weekly Sunday 2026-11-01
reset; run "2026-11-01 03:10"
assert_eq "" "$([ -e "$S/weekly" ] && echo yes)" "Sunday 03:10 no weekly yet"
assert_eq "" "$([ -e "$CALLS" ] && echo yes)" "no tools before 03:30"
run "2026-11-01 03:40"
assert_eq "" "$([ -d "$D/new" ] && echo yes)" "weekly removes all DerivedData"
assert_eq "" "$([ -d "$G/caches/build-cache-1/o" ] && echo yes)" "weekly prunes old gradle build-cache"
assert_eq yes "$([ -d "$G/caches/build-cache-1/n" ] && echo yes)" "weekly keeps new gradle build-cache"
assert_eq "" "$([ -e "$G/daemon/8/x.log" ] && echo yes)" "weekly removes old daemon log"
assert_eq "" "$([ -d "$K/cache-1/old" ] && echo yes)" "weekly prunes old konan cache child"
assert_eq yes "$([ -d "$K/cache-1/new" ] && echo yes)" "konan cache dir and new child kept"
assert_eq "" "$([ -d "$DS/old" ] && echo yes)" "weekly prunes old DeviceSupport"
assert_eq yes "$([ -d "$DS/new" ] && echo yes)" "keeps new DeviceSupport"
for c in "xcrun simctl delete unavailable" "pod cache clean --all" "brew cleanup -s" "npm cache clean --force"; do
  assert_eq 1 "$(grep -cx "$c" "$CALLS")" "weekly ran: $c"
done
assert_eq yes "$([ -f "$S/weekly" ] && echo yes)" "weekly stamp"
rm "$CALLS"; run "2026-11-01 05:00"
assert_eq "" "$([ -e "$CALLS" ] && echo yes)" "weekly once per week"
# --- emergency
reset; mkdir -p "$S"; echo 2026-10-28 > "$S/daily"; HK_FREE_GB=20 run "2026-10-28 10:00"
assert_eq "" "$([ -d "$D/old" ] && echo yes)" "emergency runs daily cleanup at 10:00"
assert_eq yes "$([ -s "$T/notified" ] && echo yes)" "still <50GB -> notified"
reset; mkdir -p "$S"; echo 2026-10-28 > "$S/daily"; HK_FREE_GB=200 run "2026-10-28 10:00"
assert_eq yes "$([ -d "$D/old" ] && echo yes)" "10:00 normal disk: nothing"
assert_eq "" "$([ -e "$T/notified" ] && echo yes)" "no notify when healthy"
# --- emergency rate limit
reset; mkdir -p "$S"; echo 2026-10-28 > "$S/daily"; HK_FREE_GB=20 run "2026-10-28 10:00"
mkdir -p "$D/again"; touch -t $OLD "$D/again"; rm "$T/notified"
HK_FREE_GB=20 run "2026-10-28 11:00"
assert_eq yes "$([ -d "$D/again" ] && echo yes)" "emergency once per day"
assert_eq "" "$([ -e "$T/notified" ] && echo yes)" "low-disk notified once per day"
HK_FREE_GB=20 run "2026-10-29 11:00"
assert_eq "" "$([ -d "$D/again" ] && echo yes)" "emergency again next day"
assert_eq yes "$([ -s "$T/notified" ] && echo yes)" "low-disk notified next day"
# --- build-roots comments/blank/CR
reset; mkdir -p "$HOME/p2/build"; mk "$HOME/p2/build/b.apk" $OLD
printf '# comment\n\n%s\r\n  \n%s  \n' "$HOME/proj" "$HOME/p2" > "$HOME/.agent-workflow/build-roots.txt"
run "2026-10-28 03:10"
assert_eq "" "$([ -e "$HOME/proj/app/build/out/a.apk" ] && echo yes)" "CR line root processed"
assert_eq "" "$([ -e "$HOME/p2/build/b.apk" ] && echo yes)" "trailing-space root processed"
assert_eq "" "$(grep -c REFUSE "$LOG" | grep -v '^0$')" "comments/blank not refused"
# --- empty HOME
assert_exit 1 "empty HOME refused" -- env HOME= bash "$H"
# --- tool failure logged
reset; printf '#!/bin/sh\nexit 3\n' > "$T/npm"; run "2026-11-01 03:40"
assert_eq 1 "$(grep -c 'failed (exit 3)' "$LOG")" "tool failure logged with code"
printf '#!/bin/sh\necho "npm $*" >> "%s"\n' "$CALLS" > "$T/npm"
# --- missing build-roots, bad root
reset; rm "$HOME/.agent-workflow/build-roots.txt"; run "2026-10-28 03:10"
assert_eq "" "$([ -d "$D/old" ] && echo yes)" "no build-roots: rest still runs"
assert_eq yes "$([ -e "$HOME/proj/app/build/out/a.apk" ] && echo yes)" "no build-roots: apk untouched"
mkdir -p "$T/outside/build"; mk "$T/outside/build/z.apk" $OLD
reset; echo "$T/outside" > "$HOME/.agent-workflow/build-roots.txt"; run "2026-10-28 03:10"
assert_eq yes "$([ -e "$T/outside/build/z.apk" ] && echo yes)" "root outside HOME refused"
assert_eq 1 "$(grep -c REFUSE "$LOG")" "refusal logged"
assert_eq yes "$([ -s "$T/notified" ] && echo yes)" "refusal notified"
# --- plist
assert_exit 0 "plist lint" -- plutil -lint "$REPO/launchd/com.agentworkflow.housekeeping.plist"
[ "$FAILS" = 0 ]
