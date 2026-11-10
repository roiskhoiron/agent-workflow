#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
B="$REPO/bin/device-preempt.sh" L="$REPO/bin/device-lock.sh"
T=$(mktemp -d)
export AGENT_LOCK_DIR="$T/locks" AGENT_WORKFLOW_STATE="$T/state" PREEMPT_TIMEOUT=5
PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf "$T"' EXIT

S="$T/stub"; mkdir -p "$S"
printf '#!/bin/bash\ntrap "exit 130" INT TERM\nwhile :; do sleep 0.2; done\n' > "$S/maestro"; chmod +x "$S/maestro"
holder() { # holder session running stub maestro + args; sets HP (session pid) and CP (child)
  bash -c "'$S/maestro' $* & echo \$! > '$T/child'; wait" & HP=$!; PIDS+=("$HP"); disown "$HP"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/child" ] && break; sleep 0.1; done
  CP=$(cat "$T/child"); rm -f "$T/child"; PIDS+=("$CP")
}
alive() { kill -0 "$1" 2>/dev/null && echo yes || echo no; }

assert_exit 2 "tanpa argumen" -- "$B"
assert_exit 1 "info device bebas" -- "$B" info android:EMU1
assert_exit 0 "take saat bebas" -- env AGENT_LOCK_PID=$$ "$B" take android:EMU1 PROJ-9-qa1
assert_eq "PROJ-9-qa1" "$("$L" who android:EMU1)" "kunci bebas langsung milik kita"
AGENT_LOCK_PID=$$ "$L" release android:EMU1 PROJ-9-qa1

# holder testing EMU1
holder --device EMU1 test f.yaml
AGENT_LOCK_PID=$HP "$L" acquire android:EMU1 PROJ-1-qa1
case $("$B" info android:EMU1) in *"owner=PROJ-1-qa1"*"testing=yes"*) r=ok;; *) r=no;; esac
assert_eq ok "$r" "info: pemilik + testing=yes"
assert_exit 0 "take dari tiket lain" -- env AGENT_LOCK_PID=$$ "$B" take android:EMU1 PROJ-2-qa1
assert_eq "PROJ-2-qa1" "$("$L" who android:EMU1)" "kunci pindah ke kita"
assert_eq no "$(alive "$CP")" "maestro pemegang lama dihentikan"
TAB=$(printf '\t')
case $(cat "$T/state/preempted/device-$HP") in "android:EMU1${TAB}PROJ-2-qa1${TAB}"*) r=ok;; *) r=no;; esac
assert_eq ok "$r" "catatan tertulis untuk pid lama"
AGENT_LOCK_PID=$$ "$L" release android:EMU1 PROJ-2-qa1

# holder testing another device: untouched; note keeps other lines, replaces same res
holder --device OTHER test f.yaml
OP=$CP
AGENT_LOCK_PID=$HP "$L" acquire android:EMU1 PROJ-1-qa1
printf 'android:X\tA\t2020-01-01 00:00\nandroid:EMU1\tOLD\t2020-01-01 00:00\n' > "$T/state/preempted/device-$HP"
assert_exit 0 "take EMU1 saat holder uji OTHER" -- env AGENT_LOCK_PID=$$ "$B" take android:EMU1 PROJ-2-qa1
assert_eq yes "$(alive "$OP")" "maestro device lain tetap hidup"
assert_eq 2 "$(wc -l < "$T/state/preempted/device-$HP" | tr -d ' ')" "baris lama diganti, lainnya tetap"
case $(grep '^android:EMU1' "$T/state/preempted/device-$HP") in "android:EMU1${TAB}PROJ-2-qa1${TAB}"*) r=ok;; *) r=no;; esac
assert_eq ok "$r" "baris EMU1 diganti"
AGENT_LOCK_PID=$$ "$L" release android:EMU1 PROJ-2-qa1

# human holder: nothing killed
holder --device PHY1 test f.yaml
AGENT_LOCK_PID=$HP "$L" acquire android:PHY1 human-PROJ-3
assert_exit 0 "take dari human" -- env AGENT_LOCK_PID=$$ "$B" take android:PHY1 PROJ-2-qa1
assert_eq yes "$(alive "$CP")" "proses human tidak dihentikan"
assert_eq yes "$([ -s "$T/state/preempted/device-$HP" ] && echo yes)" "catatan human tertulis"

[ "$FAILS" -eq 0 ]
