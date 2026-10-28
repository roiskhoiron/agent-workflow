#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
rc=0
for t in *_test.sh; do
  echo "== $t"
  bash "$t" || rc=1
done
[ $rc -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit $rc
