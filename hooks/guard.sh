#!/bin/bash
# Claude Code PreToolUse guard. stdin = hook JSON. exit 0 = allow, exit 2 + stderr = block.
# One check_<tool> function per tool; unknown tools and unparseable input are allowed.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
PROTECTED='main|master|develop'
VTAG='v[0-9]+\.[0-9]+\.[0-9]+'

block() { echo "DIBLOKIR oleh guard: $*" >&2; exit 2; }

JQ=$(command -v jq) || block "jq tidak ditemukan, guard tidak bisa memeriksa perintah. Install jq (brew install jq)."
PY=$(command -v python3)

# resolve $1 against $2 (dir); pure string, python normalizes later
join_path() { case $1 in /*) echo "$1";; *) echo "$2/$1";; esac; }

# expand leading ~ / $HOME / ${HOME}; leaves other $vars untouched
expand_home() {
  case $1 in
    '~') echo "$HOME";;
    '~/'*) echo "$HOME/${1#\~/}";;
    '$HOME'|'${HOME}') echo "$HOME";;
    '$HOME/'*) echo "$HOME/${1#\$HOME/}";;
    '${HOME}/'*) echo "$HOME/${1#\$\{HOME\}/}";;
    *) echo "$1";;
  esac
}

# every ref is a version tag vX.Y.Z (name, refs/tags/name, or name:refs/tags/name) and not a local branch
version_tags_only() { # dir ref...
  local d=$1 r s; shift
  for r; do
    s=${r%%:*}; s=${s#refs/tags/}
    case $r in *:*) [ "${r#*:}" = "refs/tags/$s" ] || return 1;; esac
    echo "$s" | grep -Eqx "$VTAG" || return 1
    case ${r%%:*} in refs/tags/*) ;; *) ! git -C "$d" show-ref -q --verify "refs/heads/$s" 2>/dev/null || return 1;; esac
  done
}

# git [global opts] push ...   ($d = directory git runs in)
# Sets GSUB_OFF = index of git's subcommand among the args (so `git rm` isn't checked as rm).
check_git() {
  local d=$wd n=$# unk=''
  while [ $# -gt 0 ]; do
    case $1 in
      -C) d=$(join_path "$(expand_home "$2")" "$wd"); shift 2;;
      -c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env) shift 2;;
      --*=*|-p|-P|--paginate|--no-pager|--bare|--no-replace-objects|--no-optional-locks|--*-pathspecs) shift;;
      -*) unk=1; shift;;
      *) break;;
    esac
  done
  GSUB_OFF=$((n - $#))
  [ -n "$AUDIT" ] && check_git_audit "$@"
  [ "$1" = worktree ] && case ${2:-} in add|remove|move) check_worktree "$d" "${@:2}";; esac
  # unknown global option may have swallowed a value: if `push` appears anywhere, treat as push
  if [ "$1" != push ] && [ -n "$unk" ]; then
    while [ $# -gt 0 ] && [ "$1" != push ]; do shift; done
  fi
  [ "$1" = push ] || return 0
  shift
  local remote='' repo='' destructive='' bulk='' refs=() r dst br
  while [ $# -gt 0 ]; do
    case $1 in
      --repo=*) repo=${1#--repo=};;
      --repo) repo=$2; shift;;
      -o|--push-option|--receive-pack|--exec) shift;;
      --force*|--mirror|--delete) destructive=1;;
      --tags|--follow-tags|--all|--branches) bulk=1;;
      --*) ;;
      -*[fd]*) destructive=1;;
      -*) ;;
      *) if [ -z "$remote" ]; then remote=$1; else refs+=("$1"); fi;;
    esac
    shift
  done
  [ -n "$remote" ] || remote=$repo  # positional remote wins over --repo
  # Release pushes version tags to origin and upstream; explicit refs only, never force/delete/bulk
  [ -z "$destructive$bulk" ] && [ ${#refs[@]} -gt 0 ] && version_tags_only "$d" "${refs[@]}" && return 0

  br=$(git -C "$d" symbolic-ref --short -q HEAD 2>/dev/null)
  if [ -z "$remote" ]; then
    remote=$(git -C "$d" config "branch.$br.pushRemote" 2>/dev/null ||
             git -C "$d" config remote.pushDefault 2>/dev/null ||
             git -C "$d" config "branch.$br.remote" 2>/dev/null)
    [ -n "$remote" ] || block "remote untuk 'git push' tidak bisa dipastikan. Tulis eksplisit: git push origin <branch>."
  fi
  if [ "$remote" != origin ]; then
    local ou ru
    ou=$(git -C "$d" remote get-url --push origin 2>/dev/null)
    ru=$(git -C "$d" remote get-url --push "$remote" 2>/dev/null || echo "$remote")
    [ -n "$ou" ] && [ "$ru" = "$ou" ] ||
      block "push ke remote '$remote' dilarang; hanya boleh ke origin (fork). Gunakan: git push origin <branch>, lalu buat PR."
  fi

  [ ${#refs[@]} -eq 0 ] && refs=(HEAD)
  for r in "${refs[@]}"; do
    dst=${r#+}; dst=${dst##*:}; dst=${dst#refs/heads/}
    [ "$dst" = HEAD ] && dst=$br
    case $r in +*|:*) ;; *) [ -n "$destructive" ] || continue;; esac
    if echo "$dst" | grep -Eqx "$PROTECTED"; then
      block "force-push/hapus branch terlindungi '$dst' dilarang. Push tanpa --force/+, atau ke branch fitur."
    fi
  done
}

audit_block() { block "$1 dilarang: mode audit hanya-baca (/audit-issue). Catat temuan di laporan, jangan ubah repo/Jira."; }

# audit mode: only read-only git subcommands; branch/tag only list, never create/delete
check_git_audit() {
  local s=${1:-} a list='' skip=''
  shift
  case $s in
    ''|show|log|grep|blame|diff|status|ls-files|ls-tree|rev-parse|rev-list|describe|cat-file|for-each-ref|show-ref|shortlog|name-rev|merge-base|help|version|--version|--help) return 0;;
    fetch) for a; do case $a in *:*) audit_block "git fetch $a (refspec menulis branch lokal)";; esac; done;;
    reflog) case ${1:-} in expire|delete) audit_block "git reflog $1";; esac;;
    branch|tag)
      for a; do
        [ -n "$skip" ] && { skip=''; continue; }
        case $a in
          -l|--list) list=1;;
          --contains|--no-contains|--merged|--no-merged|--points-at|--sort|--format) skip=1;;
          -a) [ "$s" = tag ] && audit_block "git tag -a";;
          -d|-D|-m|-M|-c|-C|-f|-u|-s|-F|-e|--delete|--move|--copy|--force|--annotate|--sign|--edit-description|--unset-upstream|--set-upstream-to*|--track*|--file*|--message*) audit_block "git $s $a";;
          -*) ;;
          *) [ -n "$list" ] || audit_block "git $s $a";;
        esac
      done;;
    remote)
      case ${1:-} in -v|--verbose) shift;; esac
      case ${1:-} in ''|get-url|show) ;; *) audit_block "git remote $1";; esac;;
    config) for a; do case $a in --get|--get-all|--get-regexp|--list|-l) return 0;; esac; done; audit_block "git config";;
    worktree) [ "${1:-}" = list ] || audit_block "git worktree ${1:-}";;
    stash) case ${1:-} in list|show) ;; *) audit_block "git stash ${1:-}";; esac;;
    *) audit_block "git $s";;
  esac
  return 0
}

# audit mode: gh/glab read-only: read verbs only (view/list/...), api GET without fields
check_forge() {
  local a prev=''
  case ${1:-} in
    ''|search|status|help|version|--version|--help|-h) ;;
    auth) [ "${2:-}" = status ] || audit_block "gh/glab auth ${2:-}";;
    api)
      for a; do
        case $a in -f*|-F*|--field*|--raw-field*|--input*) audit_block "gh/glab api $a";; esac
        case $prev in -X|--method) [ "$a" = GET ] || audit_block "gh/glab api $prev $a";; esac
        case $a in --method=*) [ "${a#*=}" = GET ] || audit_block "gh/glab api $a";; -X?*) [ "${a#-X}" = GET ] || audit_block "gh/glab api $a";; esac
        prev=$a
      done;;
    *) case ${2:-} in view|list|ls|status|diff|checks|show|watch|-h|--help) ;; *) audit_block "gh/glab $1 ${2:-}";; esac;;
  esac
  return 0
}

# true when $1 resolves inside ${TMPDIR:-/tmp}/audit or /tmp/audit (symlinks like /tmp -> /private/tmp resolved)
in_audit_dir() {
  "$PY" -c '
import os, sys
def rp(p):
    head, tail = p, ""
    while not os.path.exists(head) and head != "/":
        head, t = os.path.split(head); tail = os.path.join(t, tail) if tail else t
    return os.path.normpath(os.path.join(os.path.realpath(head), tail))
f = rp(sys.argv[1])
sys.exit(0 if any(f.startswith(rp(r).rstrip("/") + "/") for r in sys.argv[2:]) else 1)
' "$1" "${TMPDIR:-/tmp}/audit" /tmp/audit
}

# git worktree add/remove: only a sibling of the current checkout; remove only ticket
# worktrees (<repo>-<number>) and never forced, so dirty work can't be lost (rules.md, Workspace & worktree)
check_worktree() {
  local d=$1 op=$2 p='' top
  shift 2
  [ "$op" = move ] && block "git worktree move dilarang: jangan memindah worktree. Minta user."
  while [ $# -gt 0 ]; do
    case $1 in
      -b|-B|--reason) shift 2;;
      -f|--force) [ "$op" = remove ] && block "git worktree remove --force dilarang: worktree yang masih ada perubahan tidak boleh dipaksa hapus. Commit + push dulu, atau minta user."; shift;;
      -*) shift;;
      *) [ -n "$p" ] || p=$1; shift;;
    esac
  done
  [ -n "$p" ] || return 0
  [ -n "$PY" ] || block "python3 tidak ditemukan, guard tidak bisa memeriksa path worktree."
  top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || block "git worktree $op: repo tidak dikenali di $d."
  p=$("$PY" -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(join_path "$(expand_home "$p")" "$d")")
  top=$("$PY" -c 'import os,sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "$top")
  [ "${p%/*}" = "$top" ] || block "git worktree $op hanya untuk folder sejajar checkout ini ($top/<repo>-<nomor tiket>), tulis path apa adanya tanpa variabel: $p (rules.md, Workspace & worktree)."
  [ "$op" = remove ] && ! [[ ${p##*/} =~ -[0-9]+$ ]] && block "git worktree remove hanya untuk worktree tiket <repo>-<nomor tiket>: ${p##*/} bukan worktree tiket (worktree domain/milik user tidak dihapus agen)."
  return 0
}

# orca: no new projects/repos or workspaces outside the user's domain (rules.md, Workspace & worktree)
check_orca() {
  local a
  case "$1 ${2:-}" in
    'repo add'|'project setup-'*) block "orca $1 $2 dilarang: agen tidak membuat project/repo Orca baru. Minta user.";;
    'worktree create') [ -n "$AUDIT" ] && audit_block "orca worktree create";;
    'terminal split') block "orca terminal split dilarang: agen tambahan = teammate (tool Agent dengan name \"<Nama>-<Label><n>\"); panelnya dibuka Claude Code otomatis (rules.md, Orkestrasi).";;
    'terminal create'|'agent launch') block "orca $1 $2 dilarang: membuka tab baru. Agen tambahan = teammate (tool Agent dengan name), tampil sebagai panel split (rules.md, Orkestrasi).";;
    'orchestration worker-start') case " $* " in *' --agent '*|*' --agent='*) block "worker-start --agent dilarang: membuka tab baru. Agen tambahan = teammate (tool Agent dengan name) (rules.md, Orkestrasi).";; esac;;
  esac
  for a; do
    case $a in
      --no-parent|new-child|new-top-level|--worktree=new-child|--worktree=new-top-level)
        block "orca $a dilarang: semua agen bekerja di workspace domain (teammate di workspace ini). Lihat rules.md.";;
    esac
  done
}

# rm -r/-R/--recursive: every target must be strictly inside the project root
check_rm() {
  local rec='' endopt='' paths=() a bad py
  for a; do
    if [ -z "$endopt" ]; then
      case $a in
        --) endopt=1; continue;;
        --recursive) rec=1; continue;;
        --*) continue;;
        -*[rR]*) rec=1; continue;;
        -*) continue;;
      esac
    fi
    paths+=("$(expand_home "$a")")
  done
  [ -n "$rec" ] || return 0
  for a in ${paths[@]+"${paths[@]}"}; do
    case $a in *'$'*|*'`'*|'~'*|*'{}'*) block "rm -r dengan variabel/path tak pasti ('$a') dilarang. Tulis path literal di dalam proyek.";; esac
  done
  [ ${#paths[@]} -gt 0 ] || block "rm -r tanpa path literal (mis. lewat xargs) dilarang. Tulis path di dalam proyek secara eksplisit."
  bad=$("$PY" -c '
import os, sys
c, root = sys.argv[1], os.path.realpath(sys.argv[2])
for p in sys.argv[3:]:
    n = os.path.normpath(os.path.join(c, p))
    # trailing slash makes rm follow a symlink, so check its target
    r = os.path.realpath(n) if p.endswith("/") else os.path.join(os.path.realpath(os.path.dirname(n)), os.path.basename(n))
    if not r.startswith(root + os.sep):
        print(p); break
' "$wd" "$root" "${paths[@]}" 2>/dev/null) || block "path rm -r tidak bisa diverifikasi (python3 gagal)."
  [ -z "$bad" ] || block "rm -r di luar proyek ($root) dilarang: '$bad'. Hapus hanya path di dalam proyek."
}

# Tokenize like a shell (quotes kept together); one line per simple command, tokens joined by \x1f.
# Strings run by `sh -c`/`eval`, and $(...)/`...` contents, are tokenized again as extra lines.
TOKENIZER='
import json, re, shlex, sys
SEP = set("();<>|&\n")
def toks(c):
    c = re.sub(r"(?<!\\)((?:\\\\)*)\\\n", r"\1", c)  # line continuation = odd backslash run + newline (also inside single quotes: at worst over-blocks)
    try:
        l = shlex.shlex(c, posix=True, punctuation_chars="();<>|&\n")
        l.whitespace = " \t\r"  # unquoted newline separates commands
        l.whitespace_split = True; l.commenters = ""
        return list(l)
    except ValueError:  # unbalanced quotes: crude split, fail closed
        return [t.strip("\"\x27") for t in re.findall(r"[();<>|&\n]+|[^\s();<>|&]+", c)]
def segs(c, depth=0):
    out, cur, prev = [], [], ""
    for t in toks(c):
        if t and all(ch in SEP for ch in t):
            out.append(cur); cur = []; prev = t; continue
        if not t.strip(): continue  # stray escaped whitespace
        if depth < 3 and ("$(" in t or "`" in t or (re.search(r"\s", t) and (re.fullmatch(r"-\w*c", prev) or prev == "eval"))):
            out += segs(t.replace("`", " "), depth + 1)
        t = t.replace("`", "").replace("\n", " ").replace("\x1f", " ")
        cur.append(t)
        if t != "--": prev = t  # sh -c -- "cmd"
    return out + [cur]
cmd = (json.load(sys.stdin).get("tool_input") or {}).get("command") or ""
for s in segs(cmd):
    if s: print("\x1f".join(s))
'

# --- devices: locks from bin/device-lock.sh, takeover notes from bin/device-preempt.sh ---
lock_dir() { printf '%s/%s' "${AGENT_LOCK_DIR:-$HOME/.agent-workflow/locks}" "$(printf '%s' "$1" | sed 's/%/%25/g; s#/#%2F#g; s/:/%3A/g')"; }

# $$ and up to 8 ancestor pids (cached in ANC); a lock/note of any of them is our own
ancestors() {
  [ -n "${ANC:-}" ] && return 0
  local p=$$
  for _ in 0 1 2 3 4 5 6 7 8; do
    ANC="$ANC $p"
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -n "$p" ] && [ "$p" -gt 1 ] || break
  done
  ANC="$ANC "
}

# block when <res> is locked by a live pid that is not us
check_lock() {
  local d p
  d=$(lock_dir "$1"); p=$(cat "$d/pid" 2>/dev/null)
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 0
  ancestors; [[ $ANC == *" $p "* ]] && return 0
  block "device $1 dikunci $(cat "$d/owner" 2>/dev/null). Tunggu atau tanya user untuk ambil alih (devices.md → Device dipakai)."
}

# install/uninstall/pm clear (adb, android, xcrun simctl/devicectl): only on a device that is not locked by someone else.
# $1 = tool basename, $2 = ANDROID_SERIAL= seen earlier in the segment, rest = args after the tool
check_device() {
  local tool=$1 s=$2 mut='' a n
  shift 2
  case $tool in
    adb)
      while [ $# -gt 0 ]; do
        case $1 in -s) s=${2:-}; shift;; -t|-H|-P|-L) shift;; -*) ;; *) break;; esac
        [ $# -gt 0 ] && shift  # flag may be the last arg
      done
      [ -n "$s" ] || blind+=" android"
      case ${1:-} in
        uninstall|install|install-multiple) mut=1;;
        shell) [[ " ${*:2} " == *" pm clear "* ]] && mut=1;;
      esac
      [ -n "$mut" ] || return 0
      if [ -z "$s" ]; then
        s=$("${ADB:-adb}" devices 2>/dev/null | awk '$2 == "device" {print $1}')
        n=$(printf '%s' "$s" | grep -c .)
        [ "$n" -eq 1 ] || block "adb $1 tanpa device pasti ($n device terhubung): tulis -s <serial>."
      fi
      check_lock "android:$s";;
    android)
      for a; do case $a in -*) ;; *) [ "$a" = install ] && mut=1; break;; esac; done
      [ -n "$mut" ] || return 0  # `android` as a word (cd android, ls android) is not the CLI
      while [ $# -gt 0 ]; do
        case $1 in --device) s=${2:-}; shift;; --device=*) s=${1#*=};; esac
        shift
      done
      [ -n "$s" ] || block "android install tanpa device: tulis --device <serial>."
      check_lock "android:$s";;
    xcrun)
      [ "${1:-}" = simctl ] && [[ " $* " == *" booted "* ]] && blind+=" ios"
      if [ "${1:-}" = simctl ]; then
        case ${2:-} in install|uninstall) s=${3:-};; *) return 0;; esac
      elif [ "${1:-} ${2:-} ${4:-}" = "devicectl device app" ]; then
        case ${3:-} in install|uninstall) ;; *) return 0;; esac
        while [ $# -gt 0 ]; do
          case $1 in --device|-d) s=${2:-}; shift;; --device=*) s=${1#*=};; esac
          shift
        done
      else
        return 0
      fi
      case $s in ''|booted|-*) block "xcrun $1 install/uninstall tanpa udid pasti: tulis udid (bukan booted).";; esac
      check_lock "ios:$s";;
    maestro)
      [ -z "$s" ] && [[ " $* " != *" --device"* ]] && blind+=" android ios";;
  esac
  return 0
}

# takeover notes for us (device-<our pid or ancestor>): a line whose lock we hold again is dropped;
# otherwise any Bash command naming that device id, or an untargeted one on that platform ($blind), is blocked
check_preempted() {
  local dir=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/preempted cmd p f res own at keep drop t msg=''
  [ -d "$dir" ] || return 0
  cmd=$(printf '%s' "$input" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)
  ancestors
  for p in $ANC; do
    f="$dir/device-$p"; [ -f "$f" ] || continue
    keep='' drop=''
    while IFS=$'\t' read -r res own at; do
      [ -n "$res" ] || continue
      if [ "$(cat "$(lock_dir "$res")/pid" 2>/dev/null)" = "$p" ]; then drop=1; continue; fi
      keep+="$res"$'\t'"$own"$'\t'"$at"$'\n'
      [ -z "$msg" ] || continue
      t="device $res diambil alih oleh $own pada $at: berhenti, antre dengan device-pick, ulangi uji dari awal (uji terhenti ini bukan kegagalan tiket)."
      # whole id only (U1 must not match EMU1)
      if [[ $cmd =~ (^|[^A-Za-z0-9._:-])"${res#*:}"($|[^A-Za-z0-9._:-]) ]]; then msg=$t
      elif [[ "$blind " == *" ${res%%:*} "* ]]; then msg="$t Perintah tanpa target: tulis -s/--device eksplisit."
      fi
    done < "$f"
    if [ -z "$keep" ]; then rm -f "$f"
    elif [ -n "$drop" ]; then printf '%s' "$keep" > "$f.$$" && mv "$f.$$" "$f"
    fi
  done
  [ -z "$msg" ] || block "$msg"
}

check_Bash() {
  local segs w i c t prev gsub es dev='' blind=''  # blind: platforms hit by an untargeted command (set in check_device)
  [ -n "$PY" ] || block "python3 tidak ditemukan, guard tidak bisa memeriksa perintah Bash."
  segs=$(printf '%s' "$input" | "$PY" -c "$TOKENIZER" 2>/dev/null) || block "perintah Bash tidak bisa diurai oleh guard."
  root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
  wd=$cwd   # follows cd/pushd inside the chained command
  while IFS=$'\x1f' read -ra w; do
    gsub=-1; prev=''; es=''
    # any git/rm token starts a command, wherever it sits (sudo -u x, timeout 60, VAR=..., if/then, xargs ...)
    for ((i = 0; i < ${#w[@]}; i++)); do
      c=${w[$i]##*/}
      case $c in
        cd|pushd)  # only in command position, so `echo cd x` doesn't move wd
          case $prev in ''|'!'|'{'|then|do|else|if|while|until|command|builtin)
            t=$(expand_home "${w[$((i+1))]:-~}")
            case $t in *'$'*|-*) wd=/;; *) wd=$(join_path "$t" "$wd");; esac;;
          esac;;
        git) GSUB_OFF=-1; check_git "${w[@]:$((i+1))}"; gsub=$((i + 1 + GSUB_OFF));;
        orca) check_orca "${w[@]:$((i+1))}";;
        gh|glab) [ -n "$AUDIT" ] && check_forge "${w[@]:$((i+1))}";;
        rm) [ $i -eq $gsub ] || check_rm "${w[@]:$((i+1))}";;
        ANDROID_SERIAL=*) es=${w[$i]#*=};;
        adb|xcrun|android|maestro) dev=1; check_device "$c" "$es" "${w[@]:$((i+1))}";;
        ios-ui.sh) dev=1;;
      esac
      prev=${w[$i]}
    done
  done <<< "$segs"
  [ -z "$dev" ] || check_preempted
}

# Edit/Write/MultiEdit: the primary (main) worktree is read-only once the repo has a linked worktree
# (Orca pattern); a plain checkout without linked worktrees is editable.
check_edit() {
  local f d pd gd cd_
  f=$(printf '%s' "$input" | "$JQ" -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
  [ -n "$f" ] || return 0
  [ -n "$PY" ] || block "python3 tidak ditemukan, guard tidak bisa memeriksa path."
  f=$(join_path "$(expand_home "$f")" "$cwd")
  if [ -n "$AUDIT" ]; then
    in_audit_dir "$f" || audit_block "edit file di luar folder kerja audit ${TMPDIR:-/tmp}/audit/ ($f)"
    return 0
  fi
  d=$("$PY" -c 'import os,sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "$f") || return 0
  while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done  # new file: nearest existing parent
  pd=$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null) || return 0  # not in a git repo
  cd_=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null)
  case $cd_ in /*) ;; *) cd_="$d/$cd_";; esac
  gd=$(cd -P "$cd_" 2>/dev/null && pwd -P) || return 0
  pd=$(cd -P "$pd" 2>/dev/null && pwd -P) || return 0
  [ "$pd" = "$gd" ] || return 0
  [ "$(git -C "$d" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')" -gt 1 ] && block "edit file di worktree utama dilarang: $f. Kerjakan di checkout workspace domain (lihat rules.md, Workspace & worktree)."
  return 0
}

# transitionJiraIssue: only transition ids allowed for the project in ${AGENT_WORKFLOW_STATE:-~/.agent-workflow}/jira-transitions.json
check_jira() {
  local cfg=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/jira-transitions.json
  local key id proj
  key=$(printf '%s' "$input" | "$JQ" -r '.tool_input.issueIdOrKey // empty' 2>/dev/null)
  id=$(printf '%s' "$input" | "$JQ" -r '.tool_input.transition.id // empty' 2>/dev/null)
  proj=$(printf '%s' "$key" | sed -E 's/-[0-9]+$//')
  "$JQ" -e type "$cfg" >/dev/null 2>&1 || block "config transisi Jira tidak ada/rusak ($cfg). Minta user: jalankan setup transisi."
  "$JQ" -e --arg p "$proj" 'has($p)' "$cfg" >/dev/null 2>&1 || block "project '$proj' belum punya daftar transisi. Minta user: jalankan setup transisi."
  "$JQ" -e --arg p "$proj" --arg i "$id" '.[$p].allow // [] | map(tostring) | index($i) != null' "$cfg" >/dev/null 2>&1 ||
    block "transisi id '$id' untuk $proj tidak diizinkan. Done hanya dipindah kolega; pindahkan hanya ke status yang ada di daftar allow."
}

input=$(cat)
tool=$(printf '%s' "$input" | "$JQ" -r '.tool_name // empty' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | "$JQ" -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD

# read-only audit mode (/audit-issue): env AGENT_AUDIT=1, or bin/audit-mode.sh marked one of our
# ancestor pids, i.e. the Claude session running this hook (SPV). The SPV's guard records
# session-<session_id> -> pid so its teammates (agent teams, not our descendants; their Claude runs
# with --parent-session-id) are audit too while that pid marker exists.
# shortcut: shell writes (sed -i, > file) are not caught in audit mode; upgrade with a sandbox if agents start writing via shell
AUDIT=''
if [ "${AGENT_AUDIT:-}" = 1 ]; then
  AUDIT=1
else
  mk=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/audit p=$$
  if [ -d "$mk" ]; then
    for _ in 1 2 3 4 5 6 7 8; do
      if [ -f "$mk/$p" ]; then
        AUDIT=1
        sid=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty' 2>/dev/null)
        [ -n "$sid" ] && echo "$p" > "$mk/session-$sid"
        break
      fi
      read -r pp cmd < <(ps -o ppid=,command= -p "$p" 2>/dev/null)
      case $cmd in *' --parent-session-id '*)
        sid=${cmd#* --parent-session-id }; sid=${sid%% *}
        lead=$(cat "$mk/session-$sid" 2>/dev/null)
        [ -n "$lead" ] && [ -f "$mk/$lead" ] && { AUDIT=1; break; } ;;
      esac
      p=$pp
      [ -n "$p" ] && [ "$p" -gt 1 ] || break
    done
  fi
fi

case $tool in
  Bash) check_Bash;;
  Edit|Write|MultiEdit|NotebookEdit) check_edit;;
  mcp__claude_ai_Atlassian__*)
    if [ -n "$AUDIT" ]; then
      case $tool in *__create*|*__edit*|*__add*|*__update*|*__transition*) audit_block "$tool";; esac
    elif [ "$tool" = mcp__claude_ai_Atlassian__transitionJiraIssue ]; then
      check_jira
    fi;;
esac
exit 0
