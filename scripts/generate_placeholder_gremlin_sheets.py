#!/usr/bin/env python3
"""
Генерирует замену ультра-низким полоскам 1024×28: нормальные листы 64px/кадр по высоте 128.
Запуск: из корня репо  ./FocusGremlin/.venv-sprites/bin/python scripts/generate_placeholder_gremlin_sheets.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "FocusGremlin" / "Assets.xcassets"
FRAME_W = 64
H = 128


def _frame_rect(i: int) -> tuple[int, int, int, int]:
    x0 = i * FRAME_W
    return (x0, 0, x0 + FRAME_W, H)


def _draw_base_gremlin(
    draw: ImageDraw.ImageDraw,
    bbox: tuple[int, int, int, int],
    *,
    body_rgb: tuple[int, int, int],
    eye_shift: tuple[int, int] = (0, 0),
    mouth_open: float = 0.0,
) -> None:
    x0, y0, x1, y1 = bbox
    w, h = x1 - x0, y1 - y0
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2
    # тело
    pad = 6
    body = [x0 + pad, y0 + 28, x1 - pad, y1 - 10]
    draw.rounded_rectangle(body, radius=18, fill=(*body_rgb, 255), outline=(20, 90, 35, 255), width=2)
    # глаза
    ex, ey = eye_shift
    draw.ellipse([cx - 18 + ex, cy - 12 + ey, cx - 6 + ex, cy + ey], fill=(255, 255, 255, 250))
    draw.ellipse([cx + 6 + ex, cy - 12 + ey, cx + 18 + ex, cy + ey], fill=(255, 255, 255, 250))
    draw.ellipse([cx - 14 + ex, cy - 8 + ey, cx - 10 + ex, cy - 4 + ey], fill=(15, 40, 20, 255))
    draw.ellipse([cx + 10 + ex, cy - 8 + ey, cx + 14 + ex, cy - 4 + ey], fill=(15, 40, 20, 255))
    # рот
    mw = 8 + int(mouth_open * 10)
    mh = 3 + int(mouth_open * 8)
    draw.ellipse([cx - mw, cy + 14, cx + mw, cy + 14 + mh], fill=(40, 20, 30, 255))


def sheet_idle(n: int = 20) -> Image.Image:
    img = Image.new("RGBA", (n * FRAME_W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(n):
        r = _frame_rect(i)
        bob = int(4 * math.sin(i / n * math.pi * 2))
        inner = (r[0] + 4, r[1] + 4 + bob, r[2] - 4, r[3] - 4)
        _draw_base_gremlin(d, inner, body_rgb=(52, 190, 88), eye_shift=(0, bob // 2))
    return img


def sheet_typing(n: int = 20) -> Image.Image:
    img = Image.new("RGBA", (n * FRAME_W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(n):
        r = _frame_rect(i)
        tap = 1 if i % 4 < 2 else 0
        inner = (r[0] + 4, r[1] + 4, r[2] - 4, r[3] - 4)
        _draw_base_gremlin(d, inner, body_rgb=(48, 175, 95), eye_shift=(tap, 0), mouth_open=0.15)
        x0, _, x1, y1 = inner
        # «руки» на клавиатуре
        d.rounded_rectangle([x0 + 6, y1 - 18, x0 + 20, y1 - 6], radius=3, fill=(42, 160, 80, 255))
        d.rounded_rectangle([x1 - 20, y1 - 18, x1 - 6, y1 - 6], radius=3, fill=(42, 160, 80, 255))
    return img


def sheet_talking_center(n: int = 20) -> Image.Image:
    img = Image.new("RGBA", (n * FRAME_W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(n):
        r = _frame_rect(i)
        inner = (r[0] + 4, r[1] + 4, r[2] - 4, r[3] - 4)
        mo = 0.5 + 0.5 * math.sin(i / n * math.pi * 4)
        _draw_base_gremlin(d, inner, body_rgb=(55, 200, 92), mouth_open=mo)
    return img


def sheet_talking_right(n: int = 20) -> Image.Image:
    img = Image.new("RGBA", (n * FRAME_W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(n):
        r = _frame_rect(i)
        lean = int(6 * math.sin(i / max(1, n - 1) * math.pi))
        inner = (r[0] + 4 + lean, r[1] + 4, r[2] - 4 + lean, r[3] - 4)
        _draw_base_gremlin(
            d,
            inner,
            body_rgb=(50, 185, 90),
            eye_shift=(4, 0),
            mouth_open=0.4 + 0.3 * math.sin(i * 0.7),
        )
    return img


def sheet_negate(n: int = 20) -> Image.Image:
    img = Image.new("RGBA", (n * FRAME_W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(n):
        r = _frame_rect(i)
        shake = int(5 * math.sin(i * 0.9))
        inner = (r[0] + 4 + shake, r[1] + 4, r[2] - 4 + shake, r[3] - 4)
        _draw_base_gremlin(d, inner, body_rgb=(200, 72, 72), eye_shift=(shake, 0), mouth_open=0.2)
    return img


def sheet_dismiss(n: int = 19) -> Image.Image:
    img = Image.new("RGBA", (n * FRAME_W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(n):
        r = _frame_rect(i)
        fly = int((i / max(1, n - 1)) * 55)
        alpha = int(255 * (1.0 - i / (n + 3)))
        inner = (r[0] + 4, r[1] + 4 - fly, r[2] - 4, r[3] - 4 - fly)
        x0, y0, x1, y1 = inner
        body = [x0 + 6, y0 + 28, x1 - 6, y1 - 10]
        fill = (52, 190, 88, alpha)
        out = (20, 90, 35, alpha)
        d.rounded_rectangle(body, radius=18, fill=fill, outline=out, width=2)
        cx = (x0 + x1) // 2
        cy = (y0 + y1) // 2
        d.ellipse([cx - 14, cy - 12, cx - 4, cy - 2], fill=(255, 255, 255, min(250, alpha)))
        d.ellipse([cx + 4, cy - 12, cx + 14, cy - 2], fill=(255, 255, 255, min(250, alpha)))
    return img


def main() -> None:
    out_map = [
        ("GremlinIdleSheet.imageset/gremlin_idle.png", sheet_idle()),
        ("GremlinTypingSheet.imageset/gremlin_typing.png", sheet_typing()),
        ("GremlinTalkingCenterSheet.imageset/gremlin_talking_center.png", sheet_talking_center()),
        ("GremlinTalkingRightSheet.imageset/gremlin_talking_right.png", sheet_talking_right()),
        ("GremlinTalkingNegateSheet.imageset/gremlin_talking_negate.png", sheet_negate()),
        ("GremlinDismissSheet.imageset/gremlin_dismiss.png", sheet_dismiss(19)),
    ]
    for rel, im in out_map:
        path = ASSETS / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        im.save(path, "PNG")
        print(path, im.size)


if __name__ == "__main__":
    main()
