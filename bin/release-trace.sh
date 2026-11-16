#!/usr/bin/env bash
# release-trace.sh <primary-ref> <protected-ref> <PREFIX>...
# Traces each `git log --first-parent primary..protected` commit (old -> new) to
# its PR and ticket. TSV: sha7 <TAB> pr <TAB> kode <TAB> author <TAB> subject.
# pr: #N (Merge pull request #N or trailing (#N)), !N (See merge request ...!N), or -.
# kode: first <PREFIX>-<digits> in subject+body, or -.
# Exit 0 all traced, 1 some kode=- (rows still printed), 2 usage/bad ref,
# 3 primary is not an ancestor of protected (back-merge first).
[ $# -ge 3 ] || { echo "usage: $0 <primary-ref> <protected-ref> <PREFIX>..." >&2; exit 2; }
pri=$1; prot=$2; shift 2
for r in "$pri" "$prot"; do git rev-parse --verify -q "$r^{commit}" >/dev/null || { echo "ref tidak ada: $r" >&2; exit 2; }; done
git merge-base --is-ancestor "$pri" "$prot" || { echo "primary belum terkandung di protected: back-merge dulu" >&2; exit 3; }
prefixes=$(printf '%s\n' "$@" | tr a-z A-Z | paste -sd'|' -)
rc=0
while IFS=$'\x1f' read -r -d $'\x1e' sha author subj body; do
  sha=${sha#$'\n'}
  full="$subj"$'\n'"$body"
  pr=-
  if [[ $subj =~ Merge\ pull\ request\ \#([0-9]+) ]] || [[ $subj =~ \(\#([0-9]+)\)$ ]]; then pr="#${BASH_REMATCH[1]}"
  elif [[ $body =~ See\ merge\ request\ [^$'\n']*\!([0-9]+) ]]; then pr="!${BASH_REMATCH[1]}"; fi
  kode=$(printf '%s\n' "$full" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | grep -E "^($prefixes)-" | head -1)
  [ -n "$kode" ] || { kode=-; rc=1; }
  printf '%s\t%s\t%s\t%s\t%s\n' "$sha" "$pr" "$kode" "$author" "$subj"
done < <(git log --first-parent --reverse --format='%h%x1f%an%x1f%s%x1f%b%x1e' "$pri..$prot")
exit $rc
