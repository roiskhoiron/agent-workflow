#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
G="$REPO/hooks/guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
W="$T/work"
git init -q "$W"
git -C "$W" remote add origin "$T/origin.git"
git -C "$W" remote add upstream "$T/upstream.git"
git -C "$W" remote add mine "$T/origin.git"   # same URL as origin -> allowed
git -C "$W" symbolic-ref HEAD refs/heads/fix/PROJ-1

# run guard with a Bash command; cwd = $W unless 2nd arg
bash_json() { jq -cn --arg c "$1" --arg d "${2:-$W}" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'; }
check() { # expected-exit command [cwd]
  local j; j=$(bash_json "$2" "$3")
  printf '%s' "$j" | "$G" >/dev/null 2>&1
  assert_eq "$1" "$?" "[$1] $2"
}

check 0 'git push origin fix/PROJ-1'
check 2 'git push upstream fix/PROJ-1'
check 2 'git -C /x push upstream main'
check 2 'git push https://example.com/up.git main'
check 0 "git push $T/origin.git fix/x"
check 0 'git push mine fix/x'
check 2 'git push -u upstream x'
check 2 'git push --set-upstream upstream x'
check 0 'git push -u origin x'
check 2 'git -c push.default=current push upstream'
check 0 'git -c push.default=current push origin fix/x'
check 2 'git push -o ci.skip upstream x'

git -C "$W" config branch.fix/PROJ-1.remote upstream
check 2 'git push'
check 2 'git push --tags'
git -C "$W" config branch.fix/PROJ-1.remote origin
check 0 'git push'
git -C "$W" config branch.fix/PROJ-1.pushRemote upstream
check 2 'git push'
git -C "$W" config --unset branch.fix/PROJ-1.pushRemote
git -C "$W" config --unset branch.fix/PROJ-1.remote
check 2 'git push'   # no remote determinable -> fail closed

check 2 'git push --force origin main'
check 2 'git push origin +develop'
check 2 'git push --force-with-lease origin HEAD:master'
check 2 'git push -uf origin main'
check 0 'git push -f origin fix/x'
check 0 'git push --force origin fix/x'
git -C "$W" symbolic-ref HEAD refs/heads/main
check 2 'git push -f origin'   # implicit current branch main
git -C "$W" symbolic-ref HEAD refs/heads/fix/PROJ-1

check 2 'git push upstream --delete fix/x'
check 2 'git push upstream --tags'

check 2 'echo ok && git push upstream main'
check 2 'echo ok; git push upstream main'
check 2 'true || git push upstream main'
check 2 'echo x | git push upstream main'
check 0 'git status && git log'
check 2 'bash -c "git push upstream x"'
check 2 'FOO=1 git push upstream x'
check 2 'echo $(git push upstream x)'
check 2 'git push origin :main'
check 2 'git push origin --delete develop'
check 0 'git commit -m "rm stuff"'

mkdir -p "$W/build"
check 0 'rm -rf ./build'
check 0 'rm -rf build/sub "dist"'
check 2 'rm -rf ~/Library'
check 2 'rm -rf ~'
check 2 'rm -rf $HOME/x'
check 2 'rm -fr ../other'
check 2 'rm -r -f /'
check 2 'rm -rf --no-preserve-root /'
check 2 'rm -rf .'
check 2 'rm -rf build $SOMEVAR'
check 2 'cd .. && rm -rf work2'
check 2 'echo hi && rm -Rf /etc'
check 0 'rm -f ../file.txt'
check 0 "rm -rf $W/build"
check 0 'rm -rf build' "$W/build/.."
check 0 'rm -rf x' "$T"   # cwd not a repo: root = cwd
check 2 'rm -rf ../y' "$T"

# --- fix round 1 regressions ---
check 2 'GIT_SSH_COMMAND="ssh -i k" git push upstream x'
check 2 'timeout 60 git push upstream x'
check 2 'nice -n 5 git push upstream x'
check 2 'sudo -u me git push upstream x'
check 2 'git -c "core.sshCommand=ssh -i k" push upstream x'
check 2 'git -C "/a b" push upstream x'
check 0 'git -c "core.sshCommand=ssh -i k" push origin x'
check 2 'git --weird-opt val push upstream x'
check 2 'git push --repo=origin upstream main'
check 0 'git push --repo=origin'
check 2 'if true; then git push upstream x; fi'
check 2 'for b in x; do git push upstream $b; done'
check 2 '{ git push upstream x; }'
check 2 '! git push upstream x'
check 2 '\git push upstream x'
check 2 '\rm -rf ~'
check 2 'echo ~ | xargs rm -rf'
check 2 'find .. | xargs rm -rf'
check 2 'find .. -exec rm -rf {} +'
check 2 'echo "$(git push upstream x)"'
check 2 "sh -c 'cd / && rm -rf etc'"
check 0 'git rm -r --cached .'
check 0 'git commit -m "docs: rm -rf and git push upstream explained"'
check 2 'pushd .. && rm -rf work2'
check 2 'echo cd build/a/b && rm -rf ../../x'
check 0 'cd build && rm -rf ../build/sub'
# unresolvable-path rule applies only to recursive rm
check 0 'rm "$W/boxes.json"'
check 0 'find . -name x -exec rm -f {} +'
check 2 'rm -rf "$HOME"'
check 2 'rm -r $X'
check 2 'rm $X -r'
O="$T/other"; git init -q "$O"; git -C "$O" remote add origin "$T/o2.git"; git -C "$O" remote add upstream "$T/u2.git"
git -C "$O" symbolic-ref HEAD refs/heads/f; git -C "$O" config branch.f.remote upstream
git -C "$W" config branch.fix/PROJ-1.remote origin   # hook cwd tracks origin; cd target tracks upstream
check 2 "cd $O && git push"
git -C "$W" config --unset branch.fix/PROJ-1.remote
check 0 "cd $O && git push origin f"
ln -s /etc "$W/etclink"
check 2 'rm -rf etclink/'
check 0 'rm -rf etclink'
# jq missing: fail closed (simulated with a copy that looks up a nonexistent jq)
sed 's/command -v jq)/command -v jq-missing-xyz)/' "$G" > "$T/guard_nojq.sh"
assert_exit 2 "jq missing blocks" -- sh -c "echo '{\"tool_name\":\"Edit\"}' | bash '$T/guard_nojq.sh'"

check 2 "echo x
cd /
rm -rf etc"
check 2 "git --version
rm -rf ~"
check 2 "echo 'unclosed
rm -rf ~"
check 0 "git commit -m 'line1
git push upstream later'"
check 0 "echo ok
git push origin x"
check 2 "bash -c -- 'git push upstream x'"

check 2 "git push origin \\
main --force"
check 2 "git push origin main \\
--force"
check 2 "git push \\
upstream x"
check 0 "git push origin \\
fix/x --force"
# even backslash run before newline: escaped backslash, newline still separates commands
check 2 "echo a\\\\
git push upstream x"
# odd run (3): escaped backslash + continuation -> one command 'echo a\git push upstream x'
check 0 "echo a\\\\\\
git push upstream x"
check 0 "printf 'a\\\\nb' && git push origin x"

# version tags vX.Y.Z may go to any remote (Release tags after the upstream MR merges); nothing else
check 0 'git push upstream v2.3.23'
check 0 'git push origin v2.3.23'
check 0 'git push upstream refs/tags/v2.9.47'
check 0 'git push upstream v2.3.23:refs/tags/v2.3.23'
check 0 'git -C /x push upstream v10.0.1'
check 2 'git push upstream v2.3.23 main'
check 2 'git push upstream v2.3.23-rc1'
check 2 'git push upstream HEAD:refs/tags/v2.3.23'
check 2 'git push upstream main:v2.3.23'
check 2 'git push -f upstream v2.3.23'
check 2 'git push upstream +v2.3.23'
check 2 'git push upstream --delete v2.3.23'
check 2 'git push upstream :refs/tags/v2.3.23'
check 2 'git push --tags upstream v2.3.23'
check 2 'git push --follow-tags upstream v2.3.23'
git -C "$W" commit -q --allow-empty -m init && git -C "$W" branch v9.9.9
check 2 'git push upstream v9.9.9'   # a branch named like a version is still a branch

# other tools / malformed input pass through
assert_exit 0 "Edit passes" -- sh -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{},\"cwd\":\"/\"}' | '$G'"
assert_exit 0 "malformed json passes" -- sh -c "echo 'not json' | '$G'"
printf '%s' "$(bash_json 'git push upstream main')" | "$G" >/dev/null 2>"$T/err"
assert_eq "yes" "$(grep -q upstream "$T/err" && echo yes || echo no)" "block message on stderr"
assert_exit 0 "jq present: unknown tool passes" -- sh -c "echo '{\"tool_name\":\"Write\"}' | '$G'"
exit $FAILS
