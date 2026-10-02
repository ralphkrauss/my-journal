#!/usr/bin/env python3
"""Prepare the sample photos for the App Store screenshot library.

Design-time helper, like design/icon/make_icon.py. It needs Pillow and is not
run by the checks. From the repository root:

    python3 design/app-store/make_photos.py <folder with the generated PNGs>

The five photos were made with Codex's image generation from the prompts in
design/app-store/photos/PROMPTS.md, one PNG per file name below. This script
crops each to 4:3 around its center, never enlarges it, and saves it as a
progressive JPEG without metadata in design/app-store/photos/, where
seed-library.sh picks it up. To replace a photo, generate it again from its
prompt (or use a licensed photo and record it in SOURCES.md) and run this again.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "design" / "app-store" / "photos"
NAMES = ("coffee", "tomatoes", "loaf", "path", "river")
MAX_WIDTH = 2400


def four_by_three(image: Image.Image) -> Image.Image:
    """The largest 4:3 part of the image, around its center."""
    width, height = image.size
    if width * 3 > height * 4:
        crop = height * 4 // 3
        left = (width - crop) // 2
        return image.crop((left, 0, left + crop, height))
    crop = width * 3 // 4
    top = (height - crop) // 2
    return image.crop((0, top, width, top + crop))


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: make_photos.py <folder with coffee.png, tomatoes.png, ...>")
    source = Path(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    for name in NAMES:
        with Image.open(source / f"{name}.png") as original:
            image = four_by_three(original.convert("RGB"))
        if image.width > MAX_WIDTH:
            image = image.resize((MAX_WIDTH, MAX_WIDTH * 3 // 4), Image.Resampling.LANCZOS)
        target = OUT / f"{name}.jpg"
        image.save(target, quality=86, optimize=True, progressive=True)
        print("wrote", target, f"{image.width}x{image.height}")


if __name__ == "__main__":
    main()
