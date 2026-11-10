#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
W="$REPO/bin/uat-watch.sh" L="$REPO/bin/device-lock.sh"
T=$(mktemp -d)
export AGENT_LOCK_DIR="$T/locks" AGENT_LOCK_PID=$$ UAT_IDLE_SEC=2
trap 'rm -rf "$T"' EXIT
R=android:PHY1 O=human-PROJ-1

assert_exit 2 "tanpa argumen" -- "$W"

"$L" acquire $R $O
out=$(UAT_LOG_CMD='echo a; sleep 1; echo "E AndroidRuntime: FATAL EXCEPTION: main"; sleep 30' "$W" $R com.x $O "$T/o1")
case $out in *"end=idle crash=1"*) echo "  ok: idle + crash";; *) echo "  FAIL: output '$out'"; FAILS=$((FAILS+1));; esac
assert_eq "" "$("$L" who $R)" "kunci dilepas setelah idle"
grep -q 'FATAL EXCEPTION' "$T/o1/uat-crash.txt"; assert_eq 0 $? "crash tercatat"
assert_eq 2 "$(wc -l < "$T/o1/uat-log.txt" | tr -d ' ')" "log 2 baris"

"$L" acquire $R $O
( sleep 1; "$L" release $R $O; "$L" acquire $R PROJ-9-qa1 ) &
out=$(UAT_LOG_CMD='sleep 30' "$W" $R com.x $O "$T/o2"); wait
case $out in *"end=released"*) echo "  ok: released";; *) echo "  FAIL: output '$out'"; FAILS=$((FAILS+1));; esac
assert_eq "PROJ-9-qa1" "$("$L" who $R)" "kunci milik pemilik baru tidak disentuh"
"$L" release $R PROJ-9-qa1

"$L" acquire $R $O
s=$(date +%s)
UAT_LOG_CMD='for i in 1 2 3 4; do echo l$i; sleep 1; done; sleep 30' "$W" $R com.x $O "$T/o3" >/dev/null
d=$(( $(date +%s) - s ))
[ "$d" -ge 5 ]; assert_eq 0 $? "idle diulang tiap baris (durasi $d >= 5)"

pgrep -f 'sleep 30' >/dev/null; assert_eq 1 $? "tidak ada proses log tersisa"
exit $FAILS
