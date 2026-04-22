#!/usr/bin/env python3
"""Generate the GitHub social preview image (1280x640).

Editorial-dark layout matching brand §3:
    [ app icon | title + tagline | phone screenshot ]

Output: docs/social-preview.png  (upload to repo Settings → Social preview)
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.stderr.write("Pillow required. pip install Pillow\n")
    sys.exit(2)

W, H = 1280, 640
BG = (11, 16, 19, 255)         # #0B1013 brand ink
CREAM = (244, 238, 226, 255)   # #F4EEE2 brand bg
INK_DIM = (154, 150, 138, 255) # #9A968A dark-mode inkDim
CYAN = (34, 211, 238, 255)     # #22D3EE chromaCyan
MAGENTA = (225, 29, 116, 255)  # #E11D74 chromaMagenta
BORDER = (37, 42, 49, 255)     # #252A31 dark-mode border


def load_font(size: int, bold: bool = False, cjk: bool = False) -> ImageFont.ImageFont:
    # Windows fallbacks. Microsoft YaHei has CJK glyphs.
    if cjk:
        candidates = [
            "C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc",
            "C:/Windows/Fonts/simhei.ttf",
            "/System/Library/Fonts/PingFang.ttc",
        ]
    else:
        candidates = [
            "C:/Windows/Fonts/seguisb.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
            "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
                else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def draw_grid(draw: ImageDraw.ImageDraw, step: int = 40, alpha: int = 18) -> None:
    """Subtle editorial grid overlay."""
    grid_color = (*CREAM[:3], alpha)
    for x in range(0, W + 1, step):
        draw.line([(x, 0), (x, H)], fill=grid_color, width=1)
    for y in range(0, H + 1, step):
        draw.line([(0, y), (W, y)], fill=grid_color, width=1)


def draw_chromatic_corner(img: Image.Image) -> None:
    """Brand §2 glitch signature: faint RGB-split decorative marks in corners."""
    d = ImageDraw.Draw(img)
    # Top-left corner brackets
    d.line([(30, 30), (60, 30)], fill=CYAN, width=3)
    d.line([(30, 30), (30, 60)], fill=CYAN, width=3)
    # Top-right
    d.line([(W - 60, 30), (W - 30, 30)], fill=MAGENTA, width=3)
    d.line([(W - 30, 30), (W - 30, 60)], fill=MAGENTA, width=3)
    # Bottom-left
    d.line([(30, H - 60), (30, H - 30)], fill=MAGENTA, width=3)
    d.line([(30, H - 30), (60, H - 30)], fill=MAGENTA, width=3)
    # Bottom-right
    d.line([(W - 60, H - 30), (W - 30, H - 30)], fill=CYAN, width=3)
    d.line([(W - 30, H - 60), (W - 30, H - 30)], fill=CYAN, width=3)


def paste_icon(canvas: Image.Image, icon_path: Path, size: int, x: int, y: int) -> None:
    icon = Image.open(icon_path).convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    # Rounded corners via alpha mask.
    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    r = int(size * 0.22)
    mdraw.rounded_rectangle((0, 0, size, size), r, fill=255)
    canvas.paste(icon, (x, y), mask)


def paste_phone(
    canvas: Image.Image,
    screenshot: Path,
    target_h: int,
    cx: int,
    cy: int,
) -> None:
    """Paste a phone-framed screenshot. We rescale to `target_h` tall
    (preserving aspect) and add a subtle cream border + outer glow."""
    src = Image.open(screenshot).convert("RGBA")
    sw, sh = src.size
    target_w = int(sw * (target_h / sh))
    src = src.resize((target_w, target_h), Image.Resampling.LANCZOS)

    frame = Image.new("RGBA", (target_w + 12, target_h + 12), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    # Outer thin cream border (bezel).
    fd.rounded_rectangle(
        (0, 0, target_w + 11, target_h + 11),
        radius=38,
        outline=(*CREAM[:3], 100),
        width=3,
    )

    # Clip the screenshot itself into the inner rounded rect.
    mask = Image.new("L", (target_w, target_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, target_w, target_h), radius=32, fill=255
    )
    frame.paste(src, (6, 6), mask)

    # Outer glow (cyan+magenta drop-shadow in brand style).
    glow = Image.new("RGBA", (target_w + 80, target_h + 80), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle(
        (40, 40, 40 + target_w + 11, 40 + target_h + 11),
        radius=38,
        fill=(*CYAN[:3], 16),
    )
    # Shift + magenta overlay for the RGB-split hint.
    mag = Image.new("RGBA", glow.size, (0, 0, 0, 0))
    ImageDraw.Draw(mag).rounded_rectangle(
        (44, 40, 44 + target_w + 11, 40 + target_h + 11),
        radius=38,
        fill=(*MAGENTA[:3], 16),
    )
    glow.alpha_composite(mag)

    ox = cx - (target_w + 80) // 2
    oy = cy - (target_h + 80) // 2
    canvas.alpha_composite(glow, (ox, oy))
    canvas.alpha_composite(frame, (ox + 40, oy + 40))


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    icon = repo / "assets" / "branding" / "app-icon.png"
    screenshot = repo / "docs" / "screenshots" / "gallery.png"
    out = repo / "docs" / "social-preview.png"

    if not icon.is_file():
        print(f"missing: {icon}", file=sys.stderr)
        return 1
    if not screenshot.is_file():
        print(f"missing: {screenshot}", file=sys.stderr)
        return 1

    canvas = Image.new("RGBA", (W, H), BG)
    draw = ImageDraw.Draw(canvas, "RGBA")

    # Subtle grid + corner brackets (editorial decorations).
    draw_grid(draw)
    draw_chromatic_corner(canvas)

    # Left block: app icon.
    paste_icon(canvas, icon, size=220, x=80, y=(H - 220) // 2)

    # Center block: title + taglines.
    title_font = load_font(96, bold=True)
    tag_font   = load_font(28, bold=False)
    tag_font_cjk = load_font(26, bold=False, cjk=True)
    small_font = load_font(20, bold=False)

    tx = 340
    draw.text((tx, 160), "Liveback", fill=CREAM, font=title_font)
    draw.text(
        (tx, 280),
        "Make Motion Photos move again",
        fill=CREAM,
        font=tag_font,
    )
    draw.text(
        (tx, 324),
        "让 djimimo 实况图 被微信识别为三星原生",
        fill=INK_DIM,
        font=tag_font_cjk,
    )

    # Small chips: LOCAL · OFFLINE · ANDROID
    chip_y = 430
    chip_text = "LOCAL  ·  OFFLINE  ·  ANDROID 10+"
    chip_w = draw.textlength(chip_text, font=small_font)
    draw.rounded_rectangle(
        (tx - 14, chip_y - 10, tx + chip_w + 14, chip_y + 34),
        radius=18,
        outline=BORDER,
        width=2,
    )
    draw.text((tx, chip_y), chip_text, fill=INK_DIM, font=small_font)

    # Right block: phone-framed gallery screenshot.
    # Target: phone fills right 380px region, ~520 tall centered.
    paste_phone(canvas, screenshot, target_h=520, cx=1060, cy=H // 2)

    canvas.convert("RGB").save(out, format="PNG", optimize=True)
    print(f"wrote {out} ({W}x{H})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
