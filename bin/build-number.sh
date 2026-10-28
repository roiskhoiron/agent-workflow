#!/usr/bin/env bash
# build-number.sh dev KEY...        -> first ticket's number (exit 0)
# build-number.sh next name=n...    -> n+1 if all filled sources agree (exit 0);
#                                      else summary + "saran: max+1", exit 3 (ask user)
# Empty value (asc=) = source unavailable, ignored. Usage errors exit 2.
# dec STR: decimal value without octal surprises; >15 digits (after leading zeros) would overflow -> exit 2
dec() {
  local z=${1#"${1%%[!0]*}"}
  [ ${#z} -le 15 ] || { echo "number too large: $2" >&2; exit 2; }
  echo ${z:-0}
}
usage() { echo "usage: $0 dev KEY... | next name=n..." >&2; exit 2; }
case "$1" in
  dev)
    [ -n "$2" ] || usage
    case "$2" in *-[0-9]*) ;; *) echo "invalid ticket key: $2" >&2; exit 2;; esac
    n=${2##*-}
    case "$n" in ''|*[!0-9]*) echo "invalid ticket key: $2" >&2; exit 2;; esac
    dec "$n" "$2" ;;
  next)
    shift; max=-1; min=-1; lines=""
    for a in "$@"; do
      case "$a" in *=*) ;; *) echo "bad argument (want name=value): $a" >&2; exit 2;; esac
      v=${a#*=}
      [ -z "$v" ] && continue
      case "$v" in *[!0-9]*) echo "not a non-negative integer: $a" >&2; exit 2;; esac
      v=$(dec "$v" "$a") || exit 2; lines="$lines${a%%=*}: $v
"
      [ $v -gt $max ] && max=$v
      { [ $min -lt 0 ] || [ $v -lt $min ]; } && min=$v
    done
    if [ $max -ge 0 ] && [ $max -eq $min ]; then echo $((max+1)); exit 0; fi
    printf '%s' "$lines"
    [ $max -ge 0 ] && echo "saran: $((max+1))"
    exit 3 ;;
  *) usage ;;
esac
