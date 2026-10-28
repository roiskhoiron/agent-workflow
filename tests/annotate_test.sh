#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
A="$REPO/bin/annotate.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
py() { uv run --with pillow python -I "$@"; }

py -c "from PIL import Image; Image.new('RGB',(400,800),(128,128,128)).save('$T/in.png')"
echo '[{"x":20,"y":240,"w":200,"h":125,"label":"AC2 test"}]' > "$T/b.json"
echo '[{"x":20,"y":0,"w":200,"h":125,"label":"AC2 top"}]' > "$T/top.json"
echo '[{"x":20,"y":240,"w":-5,"h":"x","label":"bad"}]' > "$T/bad.json"
echo '[{"x":300,"y":700,"w":900,"h":500,"label":"clamp"}]' > "$T/clamp.json"

assert_exit 0 "annotate ok" -- py "$A" "$T/in.png" "$T/b.json" "$T/out.png"
assert_exit 0 "top box ok" -- py "$A" "$T/in.png" "$T/top.json" "$T/top.png"
assert_exit 0 "clamped box ok" -- py "$A" "$T/in.png" "$T/clamp.json" "$T/clamp.png"
assert_exit 1 "bad box rejected" -- py "$A" "$T/in.png" "$T/bad.json" "$T/bad.png"
assert_exit 1 "missing json rejected" -- py "$A" "$T/in.png" "$T/nope.json" "$T/nope.png"
echo '{' > "$T/inv.json"
assert_exit 1 "invalid json rejected" -- py "$A" "$T/in.png" "$T/inv.json" "$T/inv.png"
[ ! -e "$T/bad.png" ] && [ ! -e "$T/inv.png" ]; assert_eq 0 "$?" "no partial output on error"

# count(path, x0,y0,x1,y1, kind) -> pixels in region that are red / white
cnt() { py -c "
import sys;from PIL import Image
im=Image.open('$1').convert('RGB');x0,y0,x1,y1=map(int,sys.argv[1:5])
px=[im.getpixel((x,y)) for x in range(x0,x1) for y in range(y0,y1)]
print(sum(p==(255,255,255) for p in px) if sys.argv[5]=='w' else sum(p==(224,32,32) for p in px) if sys.argv[5]=='r' else sum(p==(128,128,128) for p in px))" "${@:2}"; }

assert_eq 0 "$([ "$(cnt $T/out.png 21 242 23 244 r)" -gt 0 ]; echo $?)" "box edge red"
assert_eq 4 "$(cnt $T/out.png 100 300 102 302 g)" "box center unchanged"
assert_eq 0 "$([ "$(cnt $T/out.png 20 200 220 240 w)" -gt 0 ]; echo $?)" "label above has white"
assert_eq 0 "$([ "$(cnt $T/top.png 20 125 220 170 w)" -gt 0 ]; echo $?)" "label below when y=0"
assert_eq 0 "$([ "$(cnt $T/clamp.png 394 700 400 800 r)" -gt 0 ]; echo $?)" "clamped edge visible"

echo "annotate_test FAILS=$FAILS"; exit $FAILS
