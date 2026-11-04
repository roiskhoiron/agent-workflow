#!/usr/bin/env bash
# README = pintu masuk pemula: setiap perintah, skrip bin/, dan MCP yang dipakai harus disebut.
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
R="$REPO/README.md"
mentioned() { grep -qF -- "$1" "$R" && echo yes || echo no; }

for d in "$REPO"/skills/*/; do
  n=$(basename "$d"); [ "$n" = _shared ] && continue
  assert_eq yes "$(mentioned "/$n")" "perintah /$n di README"
done
for f in "$REPO"/bin/*; do
  assert_eq yes "$(mentioned "$(basename "$f")")" "skrip $(basename "$f") di README"
done
for m in $(grep -rhoE "mcp__claude_ai_[A-Za-z]+(_[A-Za-z]+)*__" "$REPO/skills" "$REPO/agents" | sort -u); do
  name=$(echo "$m" | sed -E 's/^mcp__claude_ai_(.*)__$/\1/; s/_/ /g')
  assert_eq yes "$(mentioned "$name")" "MCP $name di README"
done

[ "$FAILS" -eq 0 ]
