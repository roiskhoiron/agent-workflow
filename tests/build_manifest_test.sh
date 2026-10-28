#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
B="$REPO/bin/build-number.sh"; M="$REPO/bin/manifest-check.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# --- build-number dev ---
assert_eq "1234" "$("$B" dev PROJ-1234 PROJ-1240)" "dev first ticket"
assert_eq "42" "$("$B" dev PROJ-0042)" "dev strips leading zeros"
assert_exit 2 "dev invalid key" -- "$B" dev PROJ
assert_exit 2 "dev no key" -- "$B" dev
assert_exit 2 "unknown subcommand" -- "$B" bogus
assert_exit 2 "no subcommand" -- "$B"

assert_eq "8" "$("$B" dev PROJ-08)" "dev PROJ-08 not octal"
assert_exit 2 "dev huge number" -- "$B" dev PROJ-99999999999999999999
assert_exit 2 "next huge number" -- "$B" next asc=9223372036854775807 tag=9223372036854775807
assert_exit 2 "next 16 digits" -- "$B" next asc=1234567890123456
assert_eq "1000000000000000" "$("$B" next asc=999999999999999)" "next 15 digits ok"

# --- build-number next ---
assert_eq "10" "$("$B" next asc=09)" "next asc=09 not octal"
assert_eq "58" "$("$B" next asc=57 tag=57)" "next agree -> n+1"
assert_exit 0 "next agree exit 0" -- "$B" next asc=57 tag=57
assert_eq "58" "$("$B" next asc=57 tag= project=57)" "empty source ignored"
out=$("$B" next asc=57 project=56); rc=$?
assert_eq "3" "$rc" "next disagree exit 3"
case "$out" in *"saran: 58"*) r=ok;; *) r=no;; esac; assert_eq ok "$r" "disagree prints saran: 58"
case "$out" in *asc*project*) r=ok;; *) r=no;; esac; assert_eq ok "$r" "disagree lists sources"
assert_exit 3 "next no args" -- "$B" next
out=$("$B" next asc= tag=); assert_eq "3" "$?" "all empty exit 3"
case "$out" in *saran*) r=no;; *) r=ok;; esac; assert_eq ok "$r" "all empty: no saran"
assert_exit 2 "next non-integer" -- "$B" next asc=abc
assert_exit 2 "next negative" -- "$B" next asc=-1
assert_exit 2 "next bad arg form" -- "$B" next 57

# --- manifest-check ---
G="$T/repo"; mkdir "$G"; cd "$G" || exit 1
git init -q . && git config user.email t@t && git config user.name t
git commit -q --allow-empty -m init; git tag base
git commit -q --allow-empty -m "PROJ-1 fix"
git commit -q --allow-empty -m "feat" -m "body mentions PROJ-2 and UTF-8 and OTHER-9"
assert_exit 0 "manifest equal" -- "$M" base HEAD PROJ-1 PROJ-2
assert_exit 0 "manifest args lowercase ok" -- "$M" base HEAD proj-1 proj-2
out=$("$M" base HEAD PROJ-1); rc=$?
assert_eq "1" "$rc" "branch has extra -> exit 1"
case "$out" in *"di branch tapi tidak di manifest"*PROJ-2*) r=ok;; *) r=no;; esac; assert_eq ok "$r" "extra listed"
case "$out" in *"di manifest tapi tidak di branch"*) r=no;; *) r=ok;; esac; assert_eq ok "$r" "empty list not printed"
out=$("$M" base HEAD PROJ-1 PROJ-2 PROJ-3); rc=$?
assert_eq "1" "$rc" "manifest has extra -> exit 1"
case "$out" in *"di manifest tapi tidak di branch"*PROJ-3*) r=ok;; *) r=no;; esac; assert_eq ok "$r" "missing listed"
out=$("$M" base HEAD PROJ-1 PROJ-2); case "$out" in *UTF-8*|*OTHER-9*) r=no;; *) r=ok;; esac
assert_eq ok "$r" "foreign prefixes ignored"
git commit -q --allow-empty -m "PROJ-12 only"
out=$("$M" base HEAD PROJ-1 PROJ-2); case "$out" in *PROJ-12*) r=ok;; *) r=no;; esac
assert_eq ok "$r" "PROJ-12 not matched as PROJ-1"
assert_exit 0 "PROJ-1 PROJ-2 PROJ-12 exact" -- "$M" base HEAD PROJ-1 PROJ-2 PROJ-12
git commit -q --allow-empty -m "PROJ-1 again"
assert_exit 0 "duplicates deduped" -- "$M" base HEAD PROJ-1 PROJ-2 PROJ-12
assert_exit 2 "invalid ref" -- "$M" nope HEAD PROJ-1
assert_exit 2 "no manifest keys" -- "$M" base HEAD
assert_exit 2 "too few args" -- "$M" base

[ "$FAILS" -eq 0 ] || { echo "$FAILS failures"; exit 1; }
