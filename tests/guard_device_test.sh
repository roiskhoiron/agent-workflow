#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
G="$REPO/hooks/guard.sh"
T=$(mktemp -d)
OTHER=$(sleep 60 >/dev/null 2>&1 & echo $!)  # live, not our ancestor
trap 'kill $OTHER 2>/dev/null; rm -rf "$T"' EXIT
export AGENT_LOCK_DIR="$T/locks" AGENT_WORKFLOW_STATE="$T/st" ADB="$T/adb"
printf '#!/bin/sh\n[ "$1" = devices ] && cat "%s/adb.out"\n' "$T" > "$ADB"; chmod +x "$ADB"
printf 'List of devices attached\nEMU1\tdevice\n' > "$T/adb.out"

run() { jq -cn --arg c "$1" --arg d "$T" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | "$G" 2>"$T/err" >/dev/null; echo $?; }
chk() { assert_eq "$1" "$(run "$2")" "[$1] $2"; }
lock() { # res pid owner
  local d="$AGENT_LOCK_DIR/$(printf '%s' "$1" | sed 's/%/%25/g; s#/#%2F#g; s/:/%3A/g')"
  rm -rf "$d"; mkdir -p "$d"; echo "$2" > "$d/pid"; echo "$3" > "$d/owner"; }

chk 0 'adb -s EMU1 uninstall com.x'
lock android:EMU1 $$ PROJ-1-qa1
chk 0 'adb -s EMU1 uninstall com.x'
lock android:EMU1 $OTHER PROJ-2-qa1
chk 2 'adb -s EMU1 uninstall com.x'
grep -q 'dikunci PROJ-2-qa1' "$T/err"; assert_eq 0 $? "msg owner"
chk 2 'adb -s EMU1 shell pm clear com.x'
chk 2 'adb -s EMU1 install -r a.apk'
chk 2 'ANDROID_SERIAL=EMU1 adb uninstall com.x'
chk 2 'adb uninstall com.x'
chk 2 'android install --device EMU1 a.apk'
chk 0 'adb -s EMU1 shell input tap 1 1'
rm -rf "$AGENT_LOCK_DIR"
chk 0 'adb uninstall com.x'
printf 'List of devices attached\nEMU1\tdevice\nEMU2\tdevice\n' > "$T/adb.out"
chk 2 'adb uninstall com.x'; grep -q 'tulis -s' "$T/err"; assert_eq 0 $? "msg tulis -s"

chk 2 'xcrun simctl uninstall booted com.x'; grep -q 'tulis udid' "$T/err"; assert_eq 0 $? "msg tulis udid"
chk 0 'xcrun simctl uninstall U1 com.x'
lock ios:U1 $OTHER PROJ-3-qa1
chk 2 'xcrun simctl uninstall U1 com.x'
chk 2 'xcrun devicectl device uninstall app --device U1 com.x'
chk 0 'xcrun simctl boot U1'

# takeover note for us: our test stops on EMU1, other devices untouched
mkdir -p "$T/st/preempted"; N="$T/st/preempted/device-$$"
printf 'android:EMU1\tPROJ-2-qa1\t2026-11-10 10:00\n' > "$N"
lock android:EMU1 $OTHER PROJ-2-qa1
chk 2 'maestro --device EMU1 test f.yaml'
grep -q 'diambil alih oleh PROJ-2-qa1 pada 2026-11-10 10:00' "$T/err"; assert_eq 0 $? "msg takeover"
chk 2 'adb -s EMU1 shell input tap 1 1'
chk 0 'adb -s EMU2 shell input tap 1 1'
lock android:EMU1 $$ PROJ-1-qa1
chk 0 'adb -s EMU1 shell input tap 1 1'
assert_eq no "$([ -e "$N" ] && echo yes || echo no)" "note removed after relock"
# two notes, one relocked: only that line goes, the other still blocks
printf 'android:EMU1\tPROJ-2-qa1\t2026-11-10 10:00\nios:U1\tPROJ-3-qa1\t2026-11-10 10:05\n' > "$N"
chk 0 'adb -s EMU1 shell input tap 1 1'
assert_eq 'ios:U1' "$(cut -f1 "$N")" "only relocked line dropped"
chk 2 'xcrun simctl io U1 screenshot a.png'
chk 0 'ls -la'
exit $((FAILS>0))
