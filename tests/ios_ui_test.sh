#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
U="$REPO/bin/ios-ui.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export AGENT_LOCK_DIR="$T/locks" AGENT_LOCK_PID=$$ IOS_RUNNER_CACHE="$T/cache" STUB_DIR="$T"
unset IOS_TEAM

S="$T/stub"; mkdir -p "$S"
cat > "$S/xcrun" <<'X'
#!/bin/sh
[ "$1" = simctl ] && { echo '{"devices":{"r":[{"udid":"SIM1","state":"Booted"}]}}'; exit 0; }
[ "$1 $2 $3" = "xcresulttool export attachments" ] || [ "$1 $2 $3" = "xcresulttool export metrics" ] || exit 1
o=$(echo "$@" | sed 's/.*--output-path \([^ ]*\).*/\1/'); mkdir -p "$o"
if [ "$3" = metrics ]; then echo "launch,1.2" > "$o/m.csv"; exit 0; fi
echo png > "$o/AAA.png"; echo txt > "$o/BBB.txt"
cat > "$o/manifest.json" <<J
[{"attachments":[{"exportedFileName":"AAA.png","suggestedHumanReadableName":"TC1-01_0_609E01A4-982E-4F89-98D7-A3A06A0F17F6.png"},
{"exportedFileName":"BBB.txt","suggestedHumanReadableName":"TC1-02_0_321E1A68-C79B-4E5C-99E9-F79FCE0EE61B.txt"}]}]
J
X
cat > "$S/xcodebuild" <<'X'
#!/bin/sh
case " $* " in
  *" build-for-testing "*)
    echo "$*" >> "$STUB_DIR/builds"
    d=$(echo "$@" | sed 's/.*-derivedDataPath \([^ ]*\).*/\1/'); mkdir -p "$d/Build/Products"
    touch "$d/Build/Products/AgentRunner.xctestrun" ;;
  *" test-without-building "*)
    printf '%s' "$TEST_RUNNER_AGENT_STEPS" | base64 -d > "$STUB_DIR/steps.seen"
    echo "$*" > "$STUB_DIR/test.args"
    mkdir -p "$(echo "$@" | sed 's/.*-resultBundlePath \([^ ]*\).*/\1/')"
    exit "${STUB_RC:-0}" ;;
esac
X
chmod +x "$S"/*
export XCRUN="$S/xcrun" XCODEBUILD="$S/xcodebuild"

echo '[{"launch":"com.x"},{"screenshot":"TC1-01"}]' > "$T/ok.json"
echo 'bukan json' > "$T/bad.json"
echo '[{"measure":"launch"},{"measure":"scroll"}]' > "$T/two.json"
echo '[{"launch":"com.x"},{"measure":"launch"}]' > "$T/m.json"

assert_exit 2 "tanpa argumen" -- "$U"
assert_exit 2 "steps bukan JSON array" -- "$U" SIM1 "$T/bad.json" "$T/o0"
assert_exit 2 "dua measure ditolak" -- "$U" SIM1 "$T/two.json" "$T/o0"
assert_exit 2 "iPhone fisik tanpa IOS_TEAM" -- "$U" PHYS1 "$T/ok.json" "$T/o0"

assert_exit 0 "simulator lulus" -- "$U" SIM1 "$T/ok.json" "$T/o1"
assert_eq "$(cat "$T/ok.json")" "$(cat "$T/steps.seen")" "steps sampai ke runner utuh"
assert_eq "png" "$(cat "$T/o1/TC1-01.png" 2>/dev/null)" "attachment diberi nama langkah (png)"
assert_eq "txt" "$(cat "$T/o1/TC1-02.txt" 2>/dev/null)" "attachment diberi nama langkah (txt)"
assert_eq "1" "$(grep -c . "$T/builds")" "build sekali"
grep -q "id=SIM1" "$T/test.args"; assert_eq 0 $? "destination udid"
assert_eq "no" "$([ -d "$T/o1/metrics" ] && echo yes || echo no)" "tanpa measure tidak ada metrics"

assert_exit 2 "outdir sudah berisi run.xcresult" -- "$U" SIM1 "$T/ok.json" "$T/o1"
assert_exit 0 "run kedua" -- "$U" SIM1 "$T/m.json" "$T/o2"
assert_eq "1" "$(grep -c . "$T/builds")" "run kedua pakai build cache"
assert_eq "launch,1.2" "$(cat "$T/o2/metrics/m.csv" 2>/dev/null)" "measure -> metrics diekspor"

touch "$REPO/ios-runner/AgentRunnerUITests/RunnerTests.swift"
assert_exit 0 "sumber runner berubah" -- "$U" SIM1 "$T/ok.json" "$T/o3"
assert_eq "2" "$(grep -c . "$T/builds")" "sumber lebih baru -> build ulang"

STUB_RC=65 assert_exit 65 "langkah gagal -> exit xcodebuild" -- "$U" SIM1 "$T/ok.json" "$T/o4"
STUB_RC=65 "$U" SIM1 "$T/ok.json" "$T/o5" >/dev/null 2>&1
assert_eq "png" "$(cat "$T/o5/TC1-01.png" 2>/dev/null)" "gagal tetap ekspor attachment"

IOS_TEAM=ABC123 assert_exit 0 "iPhone fisik dengan IOS_TEAM" -- "$U" PHYS1 "$T/ok.json" "$T/o6"
tail -1 "$T/builds" | grep -q "DEVELOPMENT_TEAM=ABC123.*-allowProvisioningUpdates\|-allowProvisioningUpdates.*DEVELOPMENT_TEAM=ABC123"
assert_eq 0 $? "fisik: signing team + provisioning"
tail -1 "$T/builds" | grep -q "generic/platform=iOS "; assert_eq 0 $? "fisik: build untuk device"

[ "$FAILS" -eq 0 ]
