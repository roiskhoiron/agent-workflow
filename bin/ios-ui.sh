#!/usr/bin/env bash
# Usage: ios-ui.sh <udid> <steps.json> <outdir>
# Runs steps.json through the XCUITest runner (ios-runner/) on simulator or iPhone <udid>.
# Output in <outdir>: one file per screenshot/elementShot/hierarchy step named after it
# (<name>.png, <name>.txt, <name>-frames.json), fail-step<N>.png on failure, metrics/ when a
# measure step ran, run.xcresult. Exit = xcodebuild's (0 = all steps passed); 2 = bad input.
# Env: IOS_TEAM (required for a physical iPhone: DEVELOPMENT_TEAM of the app project);
# IOS_RUNNER_CACHE (default ~/Library/Caches/agent-workflow/ios-runner); XCODEBUILD, XCRUN
# (command overrides for tests); AGENT_LOCK_PID: see device-lock.sh.
udid=$1 steps=$2 out=$3
XCODEBUILD=${XCODEBUILD:-xcodebuild} XCRUN=${XCRUN:-xcrun}
HERE="$(cd "$(dirname "$0")" && pwd -P)"
RUNNER="$HERE/../ios-runner" LOCK="$HERE/device-lock.sh"
export AGENT_LOCK_PID=${AGENT_LOCK_PID:-$PPID}
JQ=; for j in /usr/bin/jq jq; do command -v "$j" >/dev/null 2>&1 && { JQ=$j; break; }; done
die() { echo "$1" >&2; exit 2; }

[ -n "$out" ] || die "usage: $0 <udid> <steps.json> <outdir>"
[ -n "$JQ" ] || die "jq not found"
"$JQ" -e 'type=="array"' "$steps" >/dev/null 2>&1 || die "$steps bukan JSON array"
[ "$("$JQ" '[.[] | select(has("measure"))] | length' "$steps")" -le 1 ] || die "maksimal satu langkah measure per run (batas XCTest)"
[ -e "$out/run.xcresult" ] && die "$out sudah berisi run.xcresult; pakai folder baru"

if "$XCRUN" simctl list devices -j 2>/dev/null | "$JQ" -e --arg u "$udid" '[.devices[][] | select(.udid==$u)] | length > 0' >/dev/null; then
  key=sim; build=(-destination 'generic/platform=iOS Simulator')
else
  [ -n "$IOS_TEAM" ] || die "iPhone fisik butuh IOS_TEAM (DEVELOPMENT_TEAM project app, lihat devices.md)"
  key=device-$IOS_TEAM; build=(-destination 'generic/platform=iOS' -allowProvisioningUpdates "DEVELOPMENT_TEAM=$IOS_TEAM")
fi
dd="${IOS_RUNNER_CACHE:-$HOME/Library/Caches/agent-workflow/ios-runner}/$key"

xctestrun() { ls "$dd"/Build/Products/*.xctestrun 2>/dev/null | head -1; }
stale() { local x; x=$(xctestrun); [ -z "$x" ] || [ -n "$(find "$RUNNER" -type f -newer "$x" | head -1)" ]; }
if stale; then
  # one builder per cache dir; others wait, then reuse its result
  until "$LOCK" acquire "ios-runner:$key" "ios-ui-$$" >/dev/null; do sleep 2; done
  trap '"$LOCK" release "ios-runner:$key" "ios-ui-$$"' EXIT
  if stale; then
    "$XCODEBUILD" build-for-testing -project "$RUNNER/AgentRunner.xcodeproj" -scheme AgentRunner \
      "${build[@]}" -derivedDataPath "$dd" -quiet >&2 || die "build runner gagal"
  fi
fi

mkdir -p "$out"
TEST_RUNNER_AGENT_STEPS="$(base64 < "$steps" | tr -d '\n')" "$XCODEBUILD" test-without-building \
  -xctestrun "$(xctestrun)" -destination "id=$udid" -resultBundlePath "$out/run.xcresult" -quiet >&2
rc=$?

att="$out/.attachments"
"$XCRUN" xcresulttool export attachments --path "$out/run.xcresult" --output-path "$att" >/dev/null 2>&1
"$JQ" -r '.[].attachments[] | "\(.exportedFileName)\t\(.suggestedHumanReadableName)"' "$att/manifest.json" 2>/dev/null |
  while IFS=$'\t' read -r f name; do
    # "TC1-01_0_<UUID>.png" -> "TC1-01.png"
    mv "$att/$f" "$out/$(echo "$name" | sed -E 's/_[0-9]+_[0-9A-Fa-f-]{36}(\.[^.]+)$/\1/')"
  done
if [ "$("$JQ" '[.[] | select(has("measure"))] | length' "$steps")" = 1 ]; then
  "$XCRUN" xcresulttool export metrics --path "$out/run.xcresult" --output-path "$out/metrics" >/dev/null 2>&1
fi
exit $rc
