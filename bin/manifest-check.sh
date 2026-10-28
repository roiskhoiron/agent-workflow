#!/usr/bin/env bash
# manifest-check.sh <base-ref> <head-ref> <KEY>...
# Compares ticket keys in `git log base..head` (subjects + bodies, merges included)
# with the manifest keys. Exit 0 equal, 1 differ (two lists), 2 usage/bad ref.
# Only keys whose project prefix appears in the manifest count; otherwise
# strings like UTF-8 or SHA-256 would match the key regex.
[ $# -ge 3 ] || { echo "usage: $0 <base-ref> <head-ref> <KEY>..." >&2; exit 2; }
base=$1; head=$2; shift 2
man=$(printf '%s\n' "$@" | tr a-z A-Z | sort -u)
prefixes=$(printf '%s\n' "$man" | sed 's/-[0-9]*$//' | sort -u | paste -sd'|' -)
log=$(git log --format='%B' "$base..$head" 2>&1) || { echo "$log" >&2; exit 2; }
br=$(printf '%s\n' "$log" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | grep -E "^($prefixes)-" | sort -u)
extra=$(comm -23 <(printf '%s\n' "$br") <(printf '%s\n' "$man") | grep .)
missing=$(comm -13 <(printf '%s\n' "$br") <(printf '%s\n' "$man") | grep .)
[ -z "$extra$missing" ] && exit 0
[ -n "$extra" ] && printf 'di branch tapi tidak di manifest:\n%s\n' "$extra"
[ -n "$missing" ] && printf 'di manifest tapi tidak di branch:\n%s\n' "$missing"
exit 1
