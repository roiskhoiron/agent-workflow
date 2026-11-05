#!/usr/bin/env bash
# Hourly: decides daily / weekly / emergency cleanup of rebuildable caches.
# Overrides (tests): HK_NOW HK_FREE_GB HK_BUSY HK_NOTIFY XCRUN POD BREW NPM AGENT_LOCK_DIR
set -u
[ -n "${HOME:-}" ] || { echo "housekeeping: HOME is empty" >&2; exit 1; }
AW="$HOME/.agent-workflow"; STATE="$AW/state"; LOG="$AW/logs/housekeeping.log"
mkdir -p "$STATE" "$AW/logs"
NOW=${HK_NOW:-$(date +%s)}; NOW_REAL=$(date +%s)
XCRUN=${XCRUN:-xcrun}; POD=${POD:-pod}; BREW=${BREW:-brew}; NPM=${NPM:-npm}
FAILS=0

log() { echo "$(date -r "$NOW" '+%F %T') $*" >> "$LOG"; }
fail() { log "ERROR $*"; FAILS=$((FAILS+1)); }
notify() {
  if [ -n "${HK_NOTIFY:-}" ]; then "$HK_NOTIFY" "$1"
  else osascript -e 'on run a' -e 'display notification (item 1 of a) with title "housekeeping"' -e 'end run' "$1"; fi
}
safe() { # path must be a clean path under $HOME
  case "$1" in *..*) return 1;; esac
  case "$1" in "$HOME"/?*) return 0;; esac
  return 1
}
prune() { # dir days [name-glob]: delete direct children older than N days
  local d=$1 n=$2 g=${3:-*}
  safe "$d" || { fail "REFUSE $d"; return; }
  [ -d "$d" ] || return 0
  local age=(-mtime +"$n"); [ "$n" = all ] && age=(-mtime -36500)
  find "$d" -mindepth 1 -maxdepth 1 -name "$g" "${age[@]}" -exec rm -rf {} + 2>/dev/null || fail "prune $d"
  log "pruned $d >${n}d"
}
tool() { # envvar-resolved-cmd args...
  local c=$1; shift
  command -v "$c" >/dev/null 2>&1 || return 0
  "$c" "$@" >>"$LOG" 2>&1 || { fail "failed (exit $?): $c $*"; return 0; }
  log "ran $c $*"
}
free_gb() { echo "${HK_FREE_GB:-$(df -g / | awk 'NR==2{print $4}')}"; }
busy() {
  [ -n "${HK_BUSY:-}" ] && [ "$HK_BUSY" = 1 ] && return 0
  # only build:heavy counts: checkout/device/account locks belong to sessions left open for days
  "$(dirname "$0")/build-preempt.sh" reap >/dev/null 2>&1 && log "released forgotten build:heavy"
  local d=${AGENT_LOCK_DIR:-$AW/locks}/build%3Aheavy pid
  if [ -d "$d" ]; then # same stale rule as device-lock.sh: dead pid, or no pid and >=10s old
    pid=$(cat "$d/pid" 2>/dev/null)
    if [ -n "$pid" ]; then kill -0 "$pid" 2>/dev/null && return 0
    elif [ $((NOW_REAL - $(stat -f %m "$d" 2>/dev/null || echo 0))) -lt 10 ]; then return 0; fi
  fi
  [ -n "${HK_BUSY:-}" ] && return 1 # explicit 0 skips the process check
  # a running build, not an idle GradleDaemon (Android Studio keeps those alive for hours)
  pgrep -f 'xcodebuild|GradleWrapperMain|appdistribution|altool' >/dev/null 2>&1
}

daily() {
  local X="$HOME/Library/Developer/Xcode"
  prune "$X/DerivedData" 3
  local list="$AW/build-roots.txt" r
  if [ -f "$list" ]; then
    while IFS= read -r r || [ -n "$r" ]; do
      r=${r%"${r##*[![:space:]]}"} # strip trailing whitespace/CR
      case "$r" in ''|'#'*) continue;; esac
      safe "$r" || { fail "REFUSE build root $r"; continue; }
      [ -d "$r" ] || continue
      find "$r" -maxdepth 8 -path '*/build/*' \( -name '*.apk' -o -name '*.aab' -o -name '*.ipa' \) -mtime +7 -delete 2>/dev/null || fail "build outputs $r"
      log "pruned build outputs $r"
    done < "$list"
  fi
}
weekly() {
  local X="$HOME/Library/Developer/Xcode" g c
  prune "$X/DerivedData" all
  for g in "$HOME"/.gradle/caches/build-cache-* "$HOME"/.gradle/caches/transforms-*; do
    [ -d "$g" ] && prune "$g" 14
  done
  for g in "$HOME"/.gradle/daemon/*/; do
    [ -d "$g" ] && prune "${g%/}" 14 '*.log'
  done
  for c in "$HOME"/.konan/cache*; do
    [ -d "$c" ] && prune "$c" 30
  done
  light
}
light() { # safe while a build runs: nothing a build reads
  prune "$HOME/Library/Developer/Xcode/iOS DeviceSupport" 90
  tool "$XCRUN" simctl delete unavailable
  tool "$POD" cache clean --all
  tool "$BREW" cleanup -s
  tool "$NPM" cache clean --force
}
low_disk() { # once per day
  if [ "$(free_gb)" -lt 50 ] && [ ! -e "$STATE/lowdisk-$today" ]; then
    touch "$STATE/lowdisk-$today"; log "still low: $(free_gb) GB"
    notify "Disk still below 50 GB after cleanup ($(free_gb) GB free)"
  fi
}

today=$(date -r "$NOW" +%F); hm=$(date -r "$NOW" +%H%M); dow=$(date -r "$NOW" +%u)
if busy; then
  log "busy, skipping"
  if [ "$(free_gb)" -lt 50 ] && [ ! -e "$STATE/emergency-$today" ]; then
    touch "$STATE/emergency-$today"; log "emergency while busy: free $(free_gb) GB, light cleanup"
    light; low_disk
  fi
  last=$(cat "$STATE/daily" 2>/dev/null)
  if [ -n "$last" ] && [ "$last" != "$today" ] && [ "$last" != "$(date -r $((NOW - 86400)) +%F)" ] \
    && [ ! -e "$STATE/skipnote-$today" ]; then
    touch "$STATE/skipnote-$today"
    notify "housekeeping dilewati sejak $last karena build terus berjalan; cek $LOG"
  fi
  [ "$FAILS" -gt 0 ] && notify "housekeeping: $FAILS error(s), see $LOG"
  exit 0
fi
did_daily=0
if [ "$hm" -ge 0300 ] 2>/dev/null && [ "$(cat "$STATE/daily" 2>/dev/null)" != "$today" ]; then
  daily; did_daily=1; echo "$today" > "$STATE/daily"
fi
if [ "$dow" = 7 ] && [ "$hm" -ge 0330 ] && [ "$(cat "$STATE/weekly" 2>/dev/null)" != "$today" ]; then
  weekly; echo "$today" > "$STATE/weekly"
fi
if [ "$(free_gb)" -lt 50 ] && [ ! -e "$STATE/emergency-$today" ]; then
  log "emergency: free $(free_gb) GB"
  touch "$STATE/emergency-$today"
  [ "$did_daily" = 1 ] || daily
  low_disk
fi
[ "$FAILS" -gt 0 ] && notify "housekeeping: $FAILS error(s), see $LOG"
exit 0
