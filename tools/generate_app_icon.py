#!/usr/bin/env python3
"""
Generate the Typewrite Apple Edition app icon set:
  - iOS: AppIcon.appiconset/AppIcon.png (1024×1024, universal)
  - macOS: standard `idiom: mac` PNGs (resized from the master)
"""
from __future__ import annotations

import json
import os
from typing import List, Tuple

from PIL import Image, ImageDraw, ImageFilter

W = 1024
ASSETSET = os.path.join(
    os.path.dirname(__file__),
    "..",
    "typewrite_apple_edition",
    "Assets.xcassets",
    "AppIcon.appiconset",
)
OUT_IOS = os.path.join(ASSETSET, "AppIcon.png")


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def build_master() -> Image.Image:
    """1024×1024 RGB art — typewriter + paper, bold shapes for small-size readability."""
    img = Image.new("RGB", (W, W), "#e4ddd2")
    px = img.load()
    c0 = (0xE8, 0xE0, 0xD3)
    c1 = (0xD4, 0xCA, 0xBC)
    for y in range(W):
        t = y / (W - 1)
        r = int(lerp(c0[0], c1[0], t))
        g = int(lerp(c0[1], c1[1], t))
        b = int(lerp(c0[2], c1[2], t))
        for x in range(W):
            px[x, y] = (r, g, b)

    # Soft corner vignette
    vig = Image.new("L", (W, W), 0)
    dv = ImageDraw.Draw(vig)
    pad = 120
    dv.ellipse((-pad, -pad, W + pad, W + pad), fill=255)
    vig = Image.eval(vig, lambda p: 255 - p)
    vig = vig.filter(ImageFilter.GaussianBlur(radius=80))
    shade = Image.new("RGB", (W, W), (18, 16, 14))
    img = Image.composite(shade, img, vig)

    d = ImageDraw.Draw(img, "RGB")

    d.rounded_rectangle((140, 380, 884, 880), radius=56, fill="#1a1e24", outline="#0a0c0f", width=4)
    d.rounded_rectangle((170, 320, 854, 430), radius=36, fill="#222831", outline="#11151a", width=3)
    d.rounded_rectangle((190, 350, 834, 402), radius=20, fill="#0b0d10", outline="#000000", width=2)

    d.rounded_rectangle((300, 120, 724, 380), radius=14, fill="#fbf8f0", outline="#c2bdb4", width=3)
    d.line((340, 190, 680, 190), fill="#2a2a2a", width=7)
    d.line((340, 240, 600, 240), fill="#6f6a62", width=5)
    d.line((340, 280, 640, 280), fill="#6f6a62", width=5)
    d.line((340, 320, 500, 320), fill="#6f6a62", width=5)
    d.line((314, 150, 314, 360), fill="#c12b2b", width=8)

    d.polygon([(188, 420), (248, 390), (248, 440)], fill="#8a6a45", outline="#5c442a", width=2)
    d.rounded_rectangle((190, 460, 834, 840), radius=40, fill="#0f1217", outline="#2b343f", width=2)

    rng = 9
    key_w, key_h = 52, 30
    base_x, base_y = 220, 500
    row_offsets = (0, 10, 18, 10, 0)
    for row in range(5):
        off = row_offsets[row]
        y = base_y + row * 52
        for col in range(rng):
            x = base_x + off + col * 64
            d.rounded_rectangle(
                (x, y, x + key_w, y + key_h), radius=6, fill="#2a3039", outline="#4a5563", width=1
            )
            d.line((x + 8, y + 4, x + key_w - 8, y + 4), fill="#4d5662", width=1)

    d.rounded_rectangle((360, 750, 664, 805), radius=10, fill="#2a3039", outline="#5a6575", width=2)
    d.rounded_rectangle((660, 520, 800, 700), radius=20, fill="#2a333f")
    d.rounded_rectangle((120, 860, 904, 910), radius=30, fill="#2a2620")
    return img


def write_contents_json(path: str, images: List[dict]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
        f.write("\n")


def main() -> int:
    master = build_master()
    os.makedirs(ASSETSET, exist_ok=True)

    # Remove prior macOS slice files (if re-running)
    for name in os.listdir(ASSETSET):
        if name.startswith("icon_") and name.endswith(".png"):
            try:
                os.remove(os.path.join(ASSETSET, name))
            except OSError:
                pass

    master.save(OUT_IOS, "PNG", optimize=True)
    print(f"Wrote {os.path.abspath(OUT_IOS)}")

    # macOS: (filename, point_size, scale label, pixel edge)
    mac: List[Tuple[str, str, str, int]] = [
        ("icon_16x16.png", "16x16", "1x", 16),
        ("icon_16x16@2x.png", "16x16", "2x", 32),
        ("icon_32x32.png", "32x32", "1x", 32),
        ("icon_32x32@2x.png", "32x32", "2x", 64),
        ("icon_128x128.png", "128x128", "1x", 128),
        ("icon_128x128@2x.png", "128x128", "2x", 256),
        ("icon_256x256.png", "256x256", "1x", 256),
        ("icon_256x256@2x.png", "256x256", "2x", 512),
        ("icon_512x512.png", "512x512", "1x", 512),
        ("icon_512x512@2x.png", "512x512", "2x", 1024),
    ]

    for fname, psize, scale, px in mac:
        out = os.path.join(ASSETSET, fname)
        if px == 1024:
            thumb = master
        else:
            thumb = master.resize((px, px), resample=Image.LANCZOS)
        thumb.save(out, "PNG", optimize=True)
        print(f"Wrote {out}")

    images: List[dict] = [
        {
            "filename": "AppIcon.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        }
    ]
    for fname, psize, scale, _px in mac:
        images.append(
            {
                "size": psize,
                "idiom": "mac",
                "filename": fname,
                "scale": scale,
            }
        )
    write_contents_json(os.path.join(ASSETSET, "Contents.json"), images)
    print(f"Wrote {os.path.join(ASSETSET, 'Contents.json')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
