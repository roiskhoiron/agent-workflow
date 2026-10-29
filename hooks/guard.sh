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
  [ "$1" = worktree ] && [ "${2:-}" = add ] && block "git worktree add dilarang: agen bekerja di workspace domain yang dibuka user (lihat rules.md, Workspace & worktree). Butuh folder baru → minta user."
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

# orca: no new projects/repos or workspaces outside the user's domain (rules.md, Workspace & worktree)
check_orca() {
  local a
  case "$1 ${2:-}" in
    'repo add'|'project setup-'*) block "orca $1 $2 dilarang: agen tidak membuat project/repo Orca baru. Minta user.";;
    'terminal create'|'agent launch') block "orca $1 $2 dilarang: membuka tab baru. Pakai panel split: orca terminal split --terminal \"\$ORCA_TERMINAL_HANDLE\" (rules.md, Orkestrasi).";;
    'orchestration worker-start') case " $* " in *' --agent '*|*' --agent='*) block "worker-start --agent dilarang: membuka tab baru. Split panel dulu, lalu worker-start --terminal <handle panel> (rules.md, Orkestrasi).";; esac;;
  esac
  for a; do
    case $a in
      --no-parent|new-child|new-top-level|--worktree=new-child|--worktree=new-top-level)
        block "orca $a dilarang: semua agen bekerja di workspace domain (worker-start --worktree current). Lihat rules.md.";;
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

check_Bash() {
  local segs w i c t prev gsub
  [ -n "$PY" ] || block "python3 tidak ditemukan, guard tidak bisa memeriksa perintah Bash."
  segs=$(printf '%s' "$input" | "$PY" -c "$TOKENIZER" 2>/dev/null) || block "perintah Bash tidak bisa diurai oleh guard."
  root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
  wd=$cwd   # follows cd/pushd inside the chained command
  while IFS=$'\x1f' read -ra w; do
    gsub=-1; prev=''
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
        rm) [ $i -eq $gsub ] || check_rm "${w[@]:$((i+1))}";;
      esac
      prev=${w[$i]}
    done
  done <<< "$segs"
}

# Edit/Write/MultiEdit: the primary (main) worktree is read-only once the repo has a linked worktree
# (Orca pattern); a plain checkout without linked worktrees is editable.
check_edit() {
  local f d pd gd cd_
  f=$(printf '%s' "$input" | "$JQ" -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -n "$f" ] || return 0
  [ -n "$PY" ] || block "python3 tidak ditemukan, guard tidak bisa memeriksa path."
  f=$(join_path "$(expand_home "$f")" "$cwd")
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
case $tool in
  Bash) check_Bash;;
  Edit|Write|MultiEdit) check_edit;;
  mcp__claude_ai_Atlassian__transitionJiraIssue) check_jira;;
esac
exit 0
