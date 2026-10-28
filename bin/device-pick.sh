#!/usr/bin/env bash
# Usage: device-pick.sh <ios|android> <owner>
# Prints the acquired resource (ios:<udid> | android:<serial>); exit 1 if none.
# Order: connected physical -> running virtual -> boot new virtual (if <3 virtual running).
# Env: ADB, XCRUN, EMULATOR (command overrides for tests); PICK_BOOT_TIMEOUT (seconds, default 180)
# for emulator boot and for waiting on the global boot lock; AGENT_LOCK_PID: see device-lock.sh.
plat=$1 owner=$2
ADB=${ADB:-adb} XCRUN=${XCRUN:-xcrun} EMULATOR=${EMULATOR:-emulator}
TMO=${PICK_BOOT_TIMEOUT:-180}
LOCK="$(dirname "$0")/device-lock.sh"
export AGENT_LOCK_PID=${AGENT_LOCK_PID:-$PPID}
MAX_VIRTUAL=3
JQ=; for j in /usr/bin/jq jq; do command -v "$j" >/dev/null 2>&1 && { JQ=$j; break; }; done
[ -n "$JQ" ] || { echo "jq not found; cannot count virtual devices" >&2; exit 1; }

try() { "$LOCK" acquire "$1" "$owner" >/dev/null && { echo "$1"; exit 0; }; echo "busy: $1" >&2; }
adb_serials() { "$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}'; }
sims() { # state name-prefix -> udids
  "$XCRUN" simctl list devices available -j 2>/dev/null | "$JQ" -r --arg s "$1" --arg p "$2" \
    '.devices[][] | select(.state==$s and (.name|startswith($p))) | .udid'; }
wait_for() { # poll "$@" until it succeeds or TMO seconds pass
  local end=$(( $(date +%s) + TMO ))
  until "$@"; do [ "$(date +%s)" -ge "$end" ] && return 1; sleep 1; done; }
fail_boot() { echo "$1" >&2; exit 1; }

# serialise count-and-boot across pickers (own unique owner + pid so same-owner callers still exclude)
boot_lock() {
  AGENT_LOCK_PID=$$ wait_for "$LOCK" acquire picker:boot "pick-$$" >/dev/null || fail_boot "timeout waiting for boot lock"
  trap '"$LOCK" release picker:boot "pick-$$"' EXIT
}
running() { echo $(( $(adb_serials | grep -c '^emulator-') + $(sims Booted "" | grep -c .) )); }

new_emulator() { new=$(adb_serials | grep '^emulator-' | grep -vxF "$before" | head -1); [ -n "$new" ]; }
booted() { [ "$("$ADB" -s "$new" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; }

case $plat in
  android)
    for s in $(adb_serials | grep -v '^emulator-'); do try "android:$s"; done
    for s in $(adb_serials | grep '^emulator-'); do try "android:$s"; done
    boot_lock
    if [ "$(running)" -lt $MAX_VIRTUAL ]; then
      avd=$("$EMULATOR" -list-avds 2>/dev/null | head -1)
      if [ -n "$avd" ]; then
        before=$(adb_serials)
        "$EMULATOR" -avd "$avd" -no-snapshot-save -no-boot-anim >/dev/null 2>&1 &
        wait_for new_emulator || fail_boot "emulator did not appear within ${TMO}s"
        "$LOCK" acquire "android:$new" "$owner" >/dev/null || fail_boot "new emulator $new already locked"
        wait_for booted || { "$LOCK" release "android:$new" "$owner"; fail_boot "emulator $new not booted within ${TMO}s"; }
        echo "android:$new"; exit 0
      fi
    fi ;;
  ios)
    for u in $("$XCRUN" devicectl list devices 2>/dev/null | grep ' connected ' \
        | sed -n 's/.*[[:space:]]\([0-9A-Fa-f-]\{20,\}\) (UDID).*/\1/p'); do try "ios:$u"; done
    for u in $(sims Booted iPhone); do try "ios:$u"; done
    boot_lock
    if [ "$(running)" -lt $MAX_VIRTUAL ]; then
      for u in $(sims Shutdown iPhone); do
        "$LOCK" acquire "ios:$u" "$owner" >/dev/null || continue
        "$XCRUN" simctl boot "$u" >/dev/null 2>&1 && "$XCRUN" simctl bootstatus "$u" -b >/dev/null 2>&1 \
          && { echo "ios:$u"; exit 0; }
        "$LOCK" release "ios:$u" "$owner"
      done
    fi ;;
  *) echo "usage: $0 <ios|android> <owner>" >&2; exit 2 ;;
esac
echo "no device available for $plat" >&2; exit 1
