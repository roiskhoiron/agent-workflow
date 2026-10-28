#!/usr/bin/env python3
"""Usage: annotate.py <in.png> <boxes.json> <out.png>
boxes.json: [{"x":..,"y":..,"w":..,"h":..,"label":".."}] in image pixels."""
import json, sys
from PIL import Image, ImageDraw, ImageFont

RED, LINE = (224, 32, 32), 6
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def die(msg):
    print("annotate: " + msg, file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 4:
        die("usage: annotate.py <in.png> <boxes.json> <out.png>")
    src, bj, out = sys.argv[1:]
    try:
        boxes = json.load(open(bj))
        im = Image.open(src).convert("RGB")
        assert isinstance(boxes, list)
        for b in boxes:
            for k in "xywh":
                v = b[k]
                if isinstance(v, bool) or not isinstance(v, (int, float)) or v < 0:
                    raise ValueError(f"bad '{k}': {v!r}")
            b["label"] = str(b.get("label", ""))
    except Exception as e:
        die(f"invalid input: {e!r}")

    W, H = im.size
    size = max(10, round(W * 0.03))
    try:
        font = ImageFont.truetype(FONT, size)
    except OSError:
        font = ImageFont.load_default(size=size)
    d = ImageDraw.Draw(im)
    pad = size // 4
    for b in boxes:
        x0, y0 = min(int(b["x"]), W - 1), min(int(b["y"]), H - 1)
        x1, y1 = min(int(b["x"] + b["w"]), W - 1), min(int(b["y"] + b["h"]), H - 1)
        d.rectangle([x0, y0, x1, y1], outline=RED, width=LINE)
        text = b["label"]
        if not text:
            continue
        # shortcut: truncate with "…" rather than shrink font
        while len(text) > 1 and d.textlength(text, font=font) + 2 * pad > W - x0:
            text = text.rstrip("…")[:-1] + "…"
        tw = d.textlength(text, font=font)
        asc, desc = font.getmetrics()
        bh = asc + desc + 2 * pad
        ty = y0 - bh if y0 - bh >= 0 else y1
        d.rectangle([x0, ty, x0 + tw + 2 * pad, ty + bh], fill=RED)
        d.text((x0 + pad, ty + pad), text, font=font, fill=(255, 255, 255))
    im.save(out)  # saved last: no partial output on error


main()
