#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
L="$REPO/bin/device-lock.sh"; P="$REPO/bin/device-pick.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export AGENT_LOCK_DIR="$T/locks" AGENT_LOCK_PID=$$

# --- locks ---
R='account:proj:user/1'
assert_exit 0 "A acquires" -- "$L" acquire "$R" A
assert_exit 0 "A re-acquire idempotent" -- "$L" acquire "$R" A
assert_eq "A" "$("$L" acquire "$R" B)" "B sees owner A on stdout"
assert_exit 1 "B blocked" -- "$L" acquire "$R" B
assert_eq "A" "$("$L" who "$R")" "who prints owner"
"$L" release "$R" B; assert_exit 1 "release by non-owner is no-op" -- "$L" acquire "$R" B
"$L" release "$R" A
assert_exit 0 "B acquires after release" -- "$L" acquire "$R" B
"$L" release "$R" B
AGENT_LOCK_PID=999999 "$L" acquire "$R" A
assert_exit 0 "stale pid reclaimed" -- "$L" acquire "$R" B
assert_eq "B" "$("$L" who "$R")" "owner after reclaim"

# collision-free names
assert_exit 0 "enc: a acquires" -- "$L" acquire account:a:b_c A
assert_exit 0 "enc: distinct name not colliding" -- "$L" acquire account:a_b:c B
assert_eq "A" "$("$L" who account:a:b_c)" "enc: who a"
assert_eq "B" "$("$L" who account:a_b:c)" "enc: who b"
# empty pid: fresh = held, old = stale
d=$(ls -d "$AGENT_LOCK_DIR"/account%3Aa%3Ab_c); : > "$d/pid"
assert_exit 1 "fresh empty pid held" -- "$L" acquire account:a:b_c Z
touch -t 202001010000 "$d"
assert_exit 0 "old empty pid reclaimed" -- "$L" acquire account:a:b_c Z

# --- stubs ---
S="$T/stub"; mkdir -p "$S"
cat > "$S/adb" <<'X'
#!/bin/sh
[ "$1" = -s ] && { echo "${BOOT_PROP:-1}"; exit 0; }
[ "$1" = devices ] || exit 0
cat "$STUB_DIR/adb.out"; [ -f "$STUB_DIR/booted" ] && cat "$STUB_DIR/adb.after"; exit 0
X
cat > "$S/emulator" <<'X'
#!/bin/sh
[ "$1" = "-list-avds" ] && { echo Medium_Phone_API_37.0; exit 0; }
touch "$STUB_DIR/booted"
X
cat > "$S/xcrun" <<'X'
#!/bin/sh
[ "$1" = simctl ] && [ "$2" = list ] && { cat "$STUB_DIR/sim.json"; exit 0; }
[ "$1" = simctl ] && [ "$2" = boot ] && echo "$3" > "$STUB_DIR/simboot"
[ "$1" = devicectl ] && cat "$STUB_DIR/ctl.out"
exit 0
X
chmod +x "$S"/*
export PICK_BOOT_TIMEOUT=2
export STUB_DIR="$S" ADB="$S/adb" XCRUN="$S/xcrun" EMULATOR="$S/emulator"
printf 'List of devices attached\n' > "$S/adb.out"; : > "$S/adb.after"
echo '{"devices":{}}' > "$S/sim.json"; : > "$S/ctl.out"
rm -rf "$AGENT_LOCK_DIR"
pick() { "$P" "$@" 2>/dev/null; }

# unauthorized physical + no virtual running -> boots emulator
printf 'List of devices attached\nRRCW903V5RB\tunauthorized\n' > "$S/adb.out"
printf 'emulator-5554\tdevice\n' > "$S/adb.after"
assert_eq "android:emulator-5554" "$(pick android O1)" "unauthorized skipped, virtual booted"
rm -f "$S/booted"; rm -rf "$AGENT_LOCK_DIR"

# another emulator already online+locked: wait-for-device must not be trusted, new serial found
printf 'List of devices attached\nemulator-5554\tdevice\n' > "$S/adb.out"
printf 'emulator-5556\tdevice\n' > "$S/adb.after"
"$L" acquire android:emulator-5554 X >/dev/null
assert_eq "android:emulator-5556" "$(pick android O1)" "new serial picked, not the old one"
assert_eq "" "$("$L" who picker:boot)" "boot lock released"
# boot timeouts release the lock
rm -f "$S/booted"; rm -rf "$AGENT_LOCK_DIR"; : > "$S/adb.after"; printf "List of devices attached\n" > "$S/adb.out"
assert_exit 1 "no new serial -> exit 1" -- "$P" android O1
printf 'emulator-5556\tdevice\n' > "$S/adb.after"; rm -f "$S/booted"
BOOT_PROP=0 "$P" android O1 >/dev/null 2>&1; assert_eq 1 "$?" "boot_completed never 1 -> exit 1"
assert_eq "" "$("$L" who android:emulator-5556)" "lock released on boot timeout"
# global boot lock held by someone else -> no boot
rm -f "$S/booted"; AGENT_LOCK_PID=$$ "$L" acquire picker:boot other >/dev/null
assert_exit 1 "boot lock busy -> exit 1" -- "$P" android O1
[ ! -f "$S/booted" ]; assert_eq 0 "$?" "no boot while boot lock held"
rm -rf "$AGENT_LOCK_DIR"; rm -f "$S/booted"; : > "$S/adb.after"
printf 'List of devices attached\n' > "$S/adb.out"

# physical wins
printf 'List of devices attached\nRRCW903V5RB\tdevice\nemulator-5554\tdevice\n' > "$S/adb.out"
assert_eq "android:RRCW903V5RB" "$(pick android O1)" "physical preferred"
assert_eq "android:emulator-5554" "$(pick android O2)" "next owner gets running virtual"

# iOS physical (table form) and simulator
printf 'Name Hostname Identifier State Model Reality\n------ -- ---\niPhone              00008110-000A51890E45801E (UDID)       connected   iPhone 13 Pro (iPhone14,2)   physical\n' > "$S/ctl.out"
assert_eq "ios:00008110-000A51890E45801E" "$(pick ios O1)" "ios physical"
: > "$S/ctl.out"
echo '{"devices":{"rt":[{"udid":"SIM-1","name":"iPhone 15","state":"Shutdown"},{"udid":"IPAD","name":"iPad","state":"Shutdown"}]}}' > "$S/sim.json"
rm -rf "$AGENT_LOCK_DIR"; printf 'List of devices attached\n' > "$S/adb.out"
assert_eq "ios:SIM-1" "$(pick ios O1)" "ios simulator booted"
assert_eq "SIM-1" "$(cat "$S/simboot")" "simctl boot called"

# cap: 3 virtual running, all locked -> exit 1, no boot
rm -rf "$AGENT_LOCK_DIR" "$S/simboot"
printf 'List of devices attached\nemulator-5554\tdevice\nemulator-5556\tdevice\nemulator-5558\tdevice\n' > "$S/adb.out"
for s in 5554 5556 5558; do "$L" acquire "android:emulator-$s" X >/dev/null; done
assert_exit 1 "3 virtual all locked -> none" -- "$P" android O1
assert_exit 1 "cap counts across platforms" -- "$P" ios O1
[ ! -f "$S/simboot" ]; assert_eq 0 "$?" "no boot at cap"

exit $FAILS
