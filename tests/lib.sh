FAILS=0
assert_eq() { # expected actual msg
  if [ "$1" = "$2" ]; then echo "  ok: $3"; else echo "  FAIL: $3 (expected '$1', got '$2')"; FAILS=$((FAILS+1)); fi
}
assert_exit() { # code msg -- cmd...
  local want=$1 msg=$2; shift 3
  "$@" >/dev/null 2>&1; local got=$?
  assert_eq "$want" "$got" "$msg"
}
