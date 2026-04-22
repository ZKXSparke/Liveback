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


def draw_corner_hairlines(draw: ImageDraw.ImageDraw) -> None:
    """Editorial hairline accents at the four corners — tiny registration
    marks suggesting a print layout. Stays out of the text zone."""
    hair = (*CREAM[:3], 32)
    # 40-px L-marks inset 40 px from each corner, very faint.
    for (ox, oy, dx1, dy1, dx2, dy2) in [
        (40, 40,  0,  0,  40,  0),    # TL horizontal
        (40, 40,  0,  0,   0, 40),    # TL vertical
        (W - 40, 40, -40,  0,   0,  0),
        (W - 40, 40,   0,  0,   0, 40),
        (40, H - 40,  0,   0,  40,  0),
        (40, H - 40,  0, -40,   0,  0),
        (W - 40, H - 40, -40, 0, 0, 0),
        (W - 40, H - 40,   0,-40, 0, 0),
    ]:
        draw.line(
            [(ox + dx1, oy + dy1), (ox + dx2, oy + dy2)],
            fill=hair, width=1,
        )


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
    """Render a Samsung Galaxy S26 Ultra-style mockup wrapping the screenshot.

    Design cues:
      - Near-rectangular silhouette with a small corner radius (S25/S26 Ultra).
      - Thin titanium/charcoal frame, subtle inner bezel.
      - Center punch-hole camera dot near the top.
      - Thin power + volume buttons on the right edge.
      - Cyan/magenta double-glow aura behind the device (brand §2 chroma).
    """
    src = Image.open(screenshot).convert("RGBA")
    sw, sh = src.size
    screen_w = int(sw * (target_h / sh))
    screen_h = target_h

    # Phone outer dimensions (frame + bezel around screen).
    frame_pad = 7         # titanium outer frame thickness
    bezel_pad = 3         # inner black bezel
    phone_w = screen_w + 2 * (frame_pad + bezel_pad)
    phone_h = screen_h + 2 * (frame_pad + bezel_pad)
    phone_r = 38          # S26 Ultra has a modest corner radius, flatter than S23
    screen_r = phone_r - (frame_pad + bezel_pad) + 2

    phone = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    pd = ImageDraw.Draw(phone)

    # Outer titanium frame (dark charcoal gradient approximation).
    titanium = (34, 36, 40, 255)
    pd.rounded_rectangle((0, 0, phone_w - 1, phone_h - 1), radius=phone_r, fill=titanium)

    # Thin highlight line along the top edge — suggests brushed metal.
    hi = (70, 72, 76, 255)
    pd.rounded_rectangle(
        (1, 1, phone_w - 2, 2),
        radius=phone_r,
        outline=hi,
        width=1,
    )

    # Inner bezel (matte black).
    inset = frame_pad
    pd.rounded_rectangle(
        (inset, inset, phone_w - inset - 1, phone_h - inset - 1),
        radius=phone_r - frame_pad,
        fill=(6, 7, 9, 255),
    )

    # Screen area: paste the screenshot clipped to rounded rect.
    screen_inset = frame_pad + bezel_pad
    mask = Image.new("L", (screen_w, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, screen_w, screen_h), radius=screen_r, fill=255
    )
    screen = src.resize((screen_w, screen_h), Image.Resampling.LANCZOS)
    phone.paste(screen, (screen_inset, screen_inset), mask)

    # Punch-hole front camera — center, ~28 px above top of screen area at this scale.
    cam_cx = phone_w // 2
    cam_cy = screen_inset + 30
    pd.ellipse(
        (cam_cx - 7, cam_cy - 7, cam_cx + 7, cam_cy + 7),
        fill=(0, 0, 0, 255),
        outline=(22, 22, 24, 255),
    )
    # Tiny specular highlight on the lens.
    pd.ellipse(
        (cam_cx - 3, cam_cy - 4, cam_cx, cam_cy - 1),
        fill=(60, 62, 68, 255),
    )

    # Side buttons on the right edge: one thin power, one volume rocker.
    btn_x = phone_w - 2
    # Volume (upper) — one tall thin bar
    pd.rectangle(
        (btn_x, phone_h // 2 - 70, btn_x + 2, phone_h // 2 - 10),
        fill=(50, 52, 58, 255),
    )
    # Power (lower)
    pd.rectangle(
        (btn_x, phone_h // 2 + 20, btn_x + 2, phone_h // 2 + 70),
        fill=(50, 52, 58, 255),
    )

    # Double-glow aura behind the phone (cyan + magenta brand chroma).
    pad = 60
    glow = Image.new("RGBA", (phone_w + 2 * pad, phone_h + 2 * pad), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    # Cyan ring (slight left shift)
    gd.rounded_rectangle(
        (pad - 4, pad, pad - 4 + phone_w, pad + phone_h),
        radius=phone_r + 6,
        fill=(*CYAN[:3], 18),
    )
    # Magenta ring (slight right shift)
    mag_layer = Image.new("RGBA", glow.size, (0, 0, 0, 0))
    ImageDraw.Draw(mag_layer).rounded_rectangle(
        (pad + 4, pad, pad + 4 + phone_w, pad + phone_h),
        radius=phone_r + 6,
        fill=(*MAGENTA[:3], 18),
    )
    glow.alpha_composite(mag_layer)

    ox = cx - (phone_w + 2 * pad) // 2
    oy = cy - (phone_h + 2 * pad) // 2
    canvas.alpha_composite(glow, (ox, oy))
    canvas.alpha_composite(phone, (ox + pad, oy + pad))


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    icon = repo / "assets" / "branding" / "app-icon.png"
    screenshot = repo / "docs" / "screenshots" / "home.png"
    out = repo / "docs" / "social-preview.png"

    if not icon.is_file():
        print(f"missing: {icon}", file=sys.stderr)
        return 1
    if not screenshot.is_file():
        print(f"missing: {screenshot}", file=sys.stderr)
        return 1

    canvas = Image.new("RGBA", (W, H), BG)
    draw = ImageDraw.Draw(canvas, "RGBA")

    # Editorial corner accents only — no full-screen grid (hurts legibility).
    draw_corner_hairlines(draw)
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
