#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
R="$REPO/bin/release-trace.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
git init -q -b master . && git config user.email t@t && git config user.name t
git commit -q --allow-empty -m init
git checkout -q -b develop
git checkout -q -b feature/PROJ-1; git commit -q --allow-empty -m "work on PROJ-1"
git checkout -q develop
git merge -q --no-ff feature/PROJ-1 -m "Merge pull request #12 from fork/feature/PROJ-1"
git commit -q --allow-empty -m "bugfix: PROJ-2 validasi nomor (#13)"
git checkout -q -b feature/PROJ-3; git commit -q --allow-empty -m "work on PROJ-3"
git checkout -q develop
git merge -q --no-ff feature/PROJ-3 -m "Merge branch 'feature/PROJ-3' into 'develop'" -m "See merge request grp/app!7"
git commit -q --allow-empty -m "chore: rapikan UTF-8 SHA-256"

out=$("$R" master develop PROJ)
assert_eq "4" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "4 rows (first-parent)"
col() { printf '%s\n' "$out" | sed -n "$1p" | cut -f"$2"; }
assert_eq "#12" "$(col 1 2)" "a pr"; assert_eq "PROJ-1" "$(col 1 3)" "a kode"
assert_eq "#13" "$(col 2 2)" "b pr"; assert_eq "PROJ-2" "$(col 2 3)" "b kode"
assert_eq "!7" "$(col 3 2)" "c pr";  assert_eq "PROJ-3" "$(col 3 3)" "c kode"
assert_eq "-" "$(col 4 2)" "d pr";   assert_eq "-" "$(col 4 3)" "d kode (UTF-8 ignored)"
assert_exit 1 "untraced row" -- "$R" master develop PROJ
git reset -q --hard HEAD~1
assert_exit 0 "all traced" -- "$R" master develop PROJ
git checkout -q master; git commit -q --allow-empty -m "hotfix only on master"
assert_exit 3 "primary not ancestor" -- "$R" master develop PROJ
assert_exit 2 "too few args" -- "$R" master develop
assert_exit 2 "bad ref" -- "$R" nope develop PROJ

[ "$FAILS" -eq 0 ] || { echo "$FAILS failures"; exit 1; }
