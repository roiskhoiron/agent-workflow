#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
B="$REPO/bin/build-preempt.sh" L="$REPO/bin/device-lock.sh"
T=$(mktemp -d)
export AGENT_LOCK_DIR="$T/locks" AGENT_WORKFLOW_STATE="$T/state" PREEMPT_TIMEOUT=5
PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf "$T"' EXIT

S="$T/stub"; mkdir -p "$S"
for n in xcodebuild firebase gradlew fastlane; do
  printf '#!/bin/bash\ntrap "exit 130" INT TERM\nwhile :; do sleep 0.2; done\n' > "$S/$n"; chmod +x "$S/$n"
done
holder() { # holder session running stub $1 (+ args); sets HP (session pid) and CP (child)
  bash -c "'$S/$1' ${*:2} & echo \$! > '$T/child'; wait" & HP=$!; PIDS+=("$HP"); disown "$HP"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/child" ] && break; sleep 0.1; done
  CP=$(cat "$T/child"); rm -f "$T/child"; PIDS+=("$CP")
}
alive() { kill -0 "$1" 2>/dev/null && echo yes || echo no; }

assert_exit 2 "tanpa argumen" -- "$B"
assert_exit 0 "take saat kunci bebas" -- env AGENT_LOCK_PID=$$ "$B" take PROJ-9-release1
assert_eq "PROJ-9-release1" "$("$L" who build:heavy)" "kunci bebas langsung milik kita"
AGENT_LOCK_PID=$$ "$L" release build:heavy PROJ-9-release1

# holder building -> info, take, check
holder xcodebuild
AGENT_LOCK_PID=$HP "$L" acquire build:heavy PROJ-1-release1
info=$("$B" info)
case $info in *"owner=PROJ-1-release1"*"uploading=no"*) r=ok;; *) r="$info";; esac
assert_eq ok "$r" "info: pemilik + tidak upload"
assert_exit 0 "take dari build tiket lain" -- env AGENT_LOCK_PID=$$ "$B" take PROJ-2-release1
assert_eq "PROJ-2-release1" "$("$L" who build:heavy)" "kunci pindah ke kita"
assert_eq no "$(alive "$CP")" "proses build pemegang lama dihentikan"
case $("$B" check PROJ-1-release1) in *"PROJ-2-release1"*) r=ok;; *) r=no;; esac
assert_eq ok "$r" "check: pemegang lama tahu didahulukan siapa"
assert_exit 1 "check kedua: catatan sudah dibaca" -- "$B" check PROJ-1-release1
assert_exit 1 "check tiket yang tidak didahulukan" -- "$B" check PROJ-7-release1
AGENT_LOCK_PID=$$ "$L" release build:heavy PROJ-2-release1

# firebase MCP server in the holder session is not an upload
holder firebase mcp --dir .
AGENT_LOCK_PID=$HP "$L" acquire build:heavy PROJ-5-release1
case $("$B" info) in *"uploading=no"*) r=ok;; *) r=no;; esac
assert_eq ok "$r" "info: server MCP firebase bukan upload"
AGENT_LOCK_PID=$HP "$L" release build:heavy PROJ-5-release1

for up in "gradlew appDistributionUploadRelease" "fastlane android deployFirebaseBeta"; do
  holder $up
  AGENT_LOCK_PID=$HP "$L" acquire build:heavy PROJ-6-release1
  case $("$B" info) in *"uploading=yes"*) r=ok;; *) r=no;; esac
  assert_eq ok "$r" "info: $up = upload"
  AGENT_LOCK_PID=$HP "$L" release build:heavy PROJ-6-release1
done

# holder uploading -> never interrupted
holder firebase appdistribution:distribute app.apk
AGENT_LOCK_PID=$HP "$L" acquire build:heavy PROJ-3-release1
case $("$B" info) in *"uploading=yes"*) r=ok;; *) r=no;; esac
assert_eq ok "$r" "info: sedang upload"
assert_exit 3 "take ditolak saat upload" -- env AGENT_LOCK_PID=$$ "$B" take PROJ-4-release1
assert_eq "PROJ-3-release1" "$("$L" who build:heavy)" "kunci tetap milik yang upload"
assert_eq yes "$(alive "$CP")" "upload tidak dihentikan"

# reap: lock forgotten by an idle holder (no build/upload in its tree for REAP_MIN minutes)
kill "$CP" 2>/dev/null; AGENT_LOCK_PID=$$ "$L" release build:heavy PROJ-3-release1 2>/dev/null; rm -rf "$AGENT_LOCK_DIR/build%3Aheavy"
holder xcodebuild
AGENT_LOCK_PID=$HP "$L" acquire build:heavy PROJ-5-release1
touch -t 202001010000 "$AGENT_LOCK_DIR/build%3Aheavy"
assert_exit 1 "reap: holder still building" -- "$B" reap
assert_eq yes "$([ -e "$AGENT_LOCK_DIR/build%3Aheavy/seen" ] && echo yes)" "reap: building refreshes seen"
kill "$CP"; sleep 0.3
assert_exit 1 "reap: idle but seen just now" -- "$B" reap
touch -t 202001010000 "$AGENT_LOCK_DIR/build%3Aheavy/seen" "$AGENT_LOCK_DIR/build%3Aheavy"
assert_exit 0 "reap: idle > REAP_MIN -> released" -- "$B" reap
assert_eq "" "$("$L" who build:heavy)" "reap: lock free"
case $("$B" check PROJ-5-release1) in *"dilepas otomatis"*) r=ok;; *) r=no;; esac
assert_eq ok "$r" "reap: holder gets a note"
assert_exit 1 "reap: free lock -> 1" -- "$B" reap

[ "$FAILS" -eq 0 ]
