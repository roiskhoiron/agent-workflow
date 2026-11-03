#!/usr/bin/env bash
# Usage: worker-pane.sh open "<Nama> (<Label><n>)" "<command>"   → prints the pane handle
#        worker-pane.sh close "<Nama> (<Label><n>)"
# Worker panes live in the SPV's tab ($ORCA_TERMINAL_HANDLE). open reuses a live pane with the same
# pane title, else splits a new one. Orca only exposes paneTitle via `terminal show`, not `list`.
set -euo pipefail
op=${1:-} title=${2:-} spv=${ORCA_TERMINAL_HANDLE:?jalankan dari terminal Orca}
[ -n "$title" ] || { echo "usage: worker-pane.sh open <judul> <command> | close <judul>" >&2; exit 2; }

find_pane() {
  local tab h
  tab=$(orca terminal show --terminal "$spv" --json | jq -r '.result.terminal.tabId')
  for h in $(orca terminal list --json | jq -r --arg t "$tab" '.result.terminals[] | select(.tabId == $t and .connected) | .handle'); do
    [ "$(orca terminal show --terminal "$h" --json | jq -r '.result.terminal.paneTitle // empty')" = "$title" ] && { echo "$h"; return; }
  done
  return 0
}

h=$(find_pane)
case $op in
  open)
    if [ -n "$h" ]; then
      echo "pakai ulang panel $title" >&2
    else
      h=$(orca terminal split --terminal "$spv" --direction "${DIRECTION:-vertical}" --command "${3:?command}" --json | jq -r '.result.split.handle')
      orca terminal set-pane-title --terminal "$h" --title "$title" --json >/dev/null
    fi
    # a pane still busy with its previous task times out here instead of getting a second task
    orca terminal wait --terminal "$h" --for tui-idle --timeout-ms 60000 --json >/dev/null
    echo "$h";;
  close)
    [ -z "$h" ] || orca terminal close --terminal "$h" --json >/dev/null;;
  *) echo "usage: worker-pane.sh open <judul> <command> | close <judul>" >&2; exit 2;;
esac
