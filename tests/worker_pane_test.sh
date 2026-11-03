#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# fake orca: panes are files $T/panes/<handle> holding "<tabId>|<paneTitle>"; calls logged to $T/log
mkdir -p "$T/bin" "$T/panes"
cat > "$T/bin/orca" <<'EOF'
#!/usr/bin/env bash
P=$FAKE/panes; echo "$*" >> "$FAKE/log"
arg() { local k=$1; shift; while [ $# -gt 0 ]; do [ "$1" = "$k" ] && { echo "$2"; return; }; shift; done; }
case "$2" in
  show) IFS='|' read -r tab pt < "$P/$(arg --terminal "$@")"
        jq -cn --arg t "$tab" --arg p "$pt" '{result:{terminal:{tabId:$t,paneTitle:(if $p=="" then null else $p end)}}}';;
  list) for f in "$P"/*; do IFS='|' read -r tab _ < "$f"; jq -cn --arg h "${f##*/}" --arg t "$tab" '{handle:$h,tabId:$t,connected:true}'; done | jq -cs '{result:{terminals:.}}';;
  split) h=term_new$RANDOM; IFS='|' read -r tab _ < "$P/$(arg --terminal "$@")"; echo "$tab|" > "$P/$h"; jq -cn --arg h "$h" '{result:{split:{handle:$h}}}';;
  set-pane-title) f=$P/$(arg --terminal "$@"); IFS='|' read -r tab _ < "$f"; echo "$tab|$(arg --title "$@")" > "$f";;
  close) rm "$P/$(arg --terminal "$@")";;
esac
EOF
chmod +x "$T/bin/orca"
export FAKE=$T PATH="$T/bin:$PATH" ORCA_TERMINAL_HANDLE=term_spv
echo "tab1|Pak Darmo (SPV)" > "$T/panes/term_spv"
echo "tab2|Maman (Programmer1)" > "$T/panes/term_other"   # same title, other tab: not ours
W="$REPO/bin/worker-pane.sh"

h1=$("$W" open "Maman (Programmer1)" claude 2>/dev/null)
assert_eq "tab1|Maman (Programmer1)" "$(cat "$T/panes/$h1")" "new pane split in SPV tab with title"
h2=$("$W" open "Maman (Programmer1)" claude 2>/dev/null)
assert_eq "$h1" "$h2" "same title reuses the live pane"
assert_eq 1 "$(grep -c '^terminal split' "$T/log")" "only one split"
"$W" close "Maman (Programmer1)"
assert_eq 0 "$([ -e "$T/panes/$h1" ] && echo 1 || echo 0)" "close removes the pane"
assert_eq 1 "$([ -e "$T/panes/term_other" ] && echo 1 || echo 0)" "pane in other tab untouched"
"$W" close "Ujang (Programmer2)"; assert_eq 0 "$?" "close of missing pane is a no-op"
exit $FAILS
