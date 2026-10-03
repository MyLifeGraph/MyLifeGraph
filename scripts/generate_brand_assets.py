#!/usr/bin/env python3
"""Resize the approved tracked Liquid Glass artwork, without re-generating it.

Requires Pillow in the caller's Python environment. No network or credentials.
The original SVG remains the theme-tinted/monochrome shape authority.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "apps/mobile/assets/brand/app_icon_glass_source.png"


def main() -> None:
    from PIL import Image

    with Image.open(SOURCE) as source:
        artwork = source.convert("RGB")
        if artwork.width != artwork.height or artwork.width < 512:
            raise ValueError("Approved icon must be square and at least 512 pixels.")
        targets = {
            "apps/mobile/assets/brand/app_icon_glass.png": 512,
            "apps/mobile/android/app/src/main/res/drawable-nodpi/app_launcher_art.png": 512,
            "apps/mobile/web/favicon.png": 32,
        }
        for size in (192, 512):
            for name in (f"Icon-{size}.png", f"Icon-maskable-{size}.png"):
                targets[f"apps/mobile/web/icons/{name}"] = size
        sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
        for density, size in sizes.items():
            targets[f"apps/mobile/android/app/src/main/res/mipmap-{density}/ic_launcher.png"] = size
        for relative, size in targets.items():
            target = ROOT / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            artwork.resize((size, size), Image.Resampling.LANCZOS).save(target, optimize=True)
            print(f"{relative} ({size}x{size})")


if __name__ == "__main__":
    main()
