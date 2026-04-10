#!/usr/bin/env python3
"""Нормализует горизонтальный 5-кадровый лист: ровные квадратные ячейки, фиксированная высота."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

# Каждая ячейка квадратная: strip = 5 * CELL x CELL
CELL = 512
STRIP_W = 5 * CELL
STRIP_H = CELL

SHEET_NAMES = [
    "idle_1.png",
    "talking_1.png",
    "talking_2.png",
    "talking_3.png",
    "final_1.png",
]


def normalize_strip(src: Path) -> Image.Image:
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    if w <= 0 or h <= 0:
        raise ValueError("bad image size")
    # Масштаб по высоте до STRIP_H
    scale = STRIP_H / h
    nw = max(1, int(round(w * scale)))
    im = im.resize((nw, STRIP_H), Image.Resampling.LANCZOS)
    # Центр-кроп или паддинг до ровно 5 квадратов
    if nw >= STRIP_W:
        left = (nw - STRIP_W) // 2
        im = im.crop((left, 0, left + STRIP_W, STRIP_H))
    else:
        canvas = Image.new("RGBA", (STRIP_W, STRIP_H), (255, 255, 255, 255))
        x0 = (STRIP_W - nw) // 2
        canvas.paste(im, (x0, 0), im)
        im = canvas
    return im


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: normalize_gremlin_five_frame_sheet.py <source.png>", file=sys.stderr)
        return 1
    src = Path(sys.argv[1]).resolve()
    if not src.is_file():
        print(f"missing: {src}", file=sys.stderr)
        return 1
    root = Path(__file__).resolve().parents[1]
    out_dir = root / "FocusGremlin" / "Resources" / "CharacterSheets"
    out_dir.mkdir(parents=True, exist_ok=True)
    strip = normalize_strip(src)
    for name in SHEET_NAMES:
        dest = out_dir / name
        strip.save(dest, "PNG", optimize=True)
        print(dest, strip.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
