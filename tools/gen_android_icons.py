#!/usr/bin/env python3
"""Generate Android adaptive + legacy launcher icons for Liveback.

Reads the master 1024x1024 PNG (cleaned wordmark, transparent background)
and emits:

    android/app/src/main/res/
      mipmap-anydpi-v26/
        ic_launcher.xml
        ic_launcher_round.xml
      drawable/
        ic_launcher_background.xml     (#0B1013 solid)
      drawable-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/
        ic_launcher_foreground.png     (108/162/216/324/432 px)
      mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/
        ic_launcher.png                (48/72/96/144/192 px, composited)
        ic_launcher_round.png          (same as ic_launcher; round masking
                                        happens at launcher draw time)

Per Doc 3 §8:
  * adaptive canvas = 108dp, safe area = central 66dp (wordmark fits inside).
  * background layer = solid `#0B1013` (UI-Brand §3 `t.ink`).
  * foreground = wordmark centered, transparent everywhere else.

Usage:
    python tools/gen_android_icons.py

Optional overrides (see --help).
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Tuple

try:
    from PIL import Image
except ImportError:
    sys.stderr.write(
        "Pillow is required. Install with: python -m pip install Pillow\n"
    )
    sys.exit(2)

# Canvas = 108dp, safe area = 66dp per Doc 3 §8.
CANVAS_DP = 108
SAFE_DP = 66

DENSITIES = {
    "mdpi":    1.0,
    "hdpi":    1.5,
    "xhdpi":   2.0,
    "xxhdpi":  3.0,
    "xxxhdpi": 4.0,
}

# Legacy launcher icon (pre-API-26 fallback): 48dp @ each density.
LEGACY_DP = 48

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""

BACKGROUND_XML_TEMPLATE = """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
       android:shape="rectangle">
    <solid android:color="{color}" />
</shape>
"""


def parse_color(s: str) -> Tuple[int, int, int, int]:
    s = s.lstrip("#")
    if len(s) == 6:
        r, g, b = int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)
        return r, g, b, 255
    if len(s) == 8:
        r, g, b, a = int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), int(s[6:8], 16)
        return r, g, b, a
    raise ValueError(f"Unparseable color: {s!r}")


def crop_transparent(img: Image.Image) -> Image.Image:
    """Tight-crop the image to its non-transparent bounding box."""
    alpha = img.split()[-1] if img.mode == "RGBA" else None
    if alpha is None:
        return img
    bbox = alpha.getbbox()
    if bbox is None:
        return img
    return img.crop(bbox)


def render_foreground(
    master: Image.Image, px: int, inset_factor: float
) -> Image.Image:
    """Render the 108dp adaptive-icon foreground canvas at ``px`` pixels.

    The master is a fully-rendered icon (opaque #0B1013 bg + grid + wordmark
    baked in). Scale it to ``inset_factor * px`` centered on a transparent
    canvas so the wordmark gets breathing room from the visible edge on
    square-masked launchers. The transparent margin falls back to the
    adaptive-icon background layer (#0B1013) — same color as the source bg,
    so the seam is invisible.

    inset_factor = 1.0 → full bleed, wordmark kisses the edge.
    inset_factor = 0.88 → ~6% margin each side, comfortable breathing room.
    inset_factor = 0.61 → scales to 66dp safe area (wordmark-only launchers).
    """
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    rgba = master.convert("RGBA")
    inner = max(1, int(round(px * inset_factor)))
    scaled = rgba.resize((inner, inner), Image.Resampling.LANCZOS)
    off = (px - inner) // 2
    canvas.paste(scaled, (off, off), scaled)
    return canvas


def render_legacy(
    master: Image.Image,
    px: int,
    bg: Tuple[int, int, int, int],
    inset_factor: float,
) -> Image.Image:
    """Legacy mipmap (pre-API 26): composite background + inset foreground.

    Pre-API-26 launchers DON'T apply the adaptive-icon background; the PNG
    must be fully opaque. Fill with ``bg`` then paste the inset-scaled source.
    Result: ``bg`` fills the breathing-room margin (matches the source's
    own bg color so the composition looks seamless).
    """
    canvas = Image.new("RGBA", (px, px), bg)
    rgba = master.convert("RGBA")
    inner = max(1, int(round(px * inset_factor)))
    scaled = rgba.resize((inner, inner), Image.Resampling.LANCZOS)
    off = (px - inner) // 2
    canvas.paste(scaled, (off, off), scaled)
    return canvas


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--master",
        default=str(repo_root / "design-v2" / "project" / "assets" / "app-icon.png"),
        help="Master 1024x1024 PNG (transparent bg).",
    )
    ap.add_argument(
        "--out",
        default=str(repo_root / "android" / "app" / "src" / "main" / "res"),
        help="Android res/ root.",
    )
    ap.add_argument(
        "--bg-color",
        default="#0B1013",
        help="Background color (hex). Default: brand t.ink.",
    )
    ap.add_argument(
        "--inset",
        type=float,
        default=0.88,
        help="Scale factor applied to the source before compositing. "
        "1.0 = full bleed; 0.88 = ~6%% margin each side (default, "
        "comfortable breathing room).",
    )
    args = ap.parse_args()

    master_path = Path(args.master)
    if not master_path.is_file():
        sys.stderr.write(f"error: master icon missing: {master_path}\n")
        return 1

    res_root = Path(args.out)
    res_root.mkdir(parents=True, exist_ok=True)
    bg_rgba = parse_color(args.bg_color)

    master = Image.open(master_path)

    # 1. mipmap-anydpi-v26 descriptors (2 files, identical).
    anydpi_dir = res_root / "mipmap-anydpi-v26"
    anydpi_dir.mkdir(parents=True, exist_ok=True)
    (anydpi_dir / "ic_launcher.xml").write_text(ADAPTIVE_XML, encoding="utf-8")
    (anydpi_dir / "ic_launcher_round.xml").write_text(ADAPTIVE_XML, encoding="utf-8")

    # 2. drawable/ic_launcher_background.xml (solid color).
    drawable_dir = res_root / "drawable"
    drawable_dir.mkdir(parents=True, exist_ok=True)
    (drawable_dir / "ic_launcher_background.xml").write_text(
        BACKGROUND_XML_TEMPLATE.format(color=args.bg_color),
        encoding="utf-8",
    )

    emitted: list[str] = []

    # 3. drawable-*dpi/ic_launcher_foreground.png per density (108dp).
    for dpi, scale in DENSITIES.items():
        px = int(round(CANVAS_DP * scale))
        out_dir = res_root / f"drawable-{dpi}"
        out_dir.mkdir(parents=True, exist_ok=True)
        fg = render_foreground(master, px, args.inset)
        out_path = out_dir / "ic_launcher_foreground.png"
        fg.save(out_path, format="PNG", optimize=True)
        emitted.append(f"{dpi}/{px}px (fg)")

    # 4. mipmap-*dpi/ic_launcher.png legacy bitmap (48dp).
    for dpi, scale in DENSITIES.items():
        px = int(round(LEGACY_DP * scale))
        out_dir = res_root / f"mipmap-{dpi}"
        out_dir.mkdir(parents=True, exist_ok=True)
        legacy = render_legacy(master, px, bg_rgba, args.inset)
        legacy.save(out_dir / "ic_launcher.png", format="PNG", optimize=True)
        # roundIcon lands on the same artwork; the launcher crops it with
        # a round mask at draw time.
        legacy.save(out_dir / "ic_launcher_round.png", format="PNG", optimize=True)
        emitted.append(f"{dpi}/{px}px (legacy)")

    print("ok — emitted:", ", ".join(emitted))
    print(f"     res root: {res_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
