#!/usr/bin/env python3
"""Turns the raw spec captures of one device into the small PNGs the repository keeps.

Usage: process.py <iphone|ipad|mac> <raw-folder> <output-folder>

A capture is half its native size (iPhone 603 x 1311, iPad 1210 x 834, a Mac window at one
pixel per point), without alpha and with at most 256 colours, which keeps a screen with a photo
under about 200 KB. Files named failed-* and the accessibility trees (.txt) are not copied.
Needs Pillow, like design/app-store/make_screenshots.py; without it the captures are resized
with sips and keep their colours (and are larger).
"""

import re
import subprocess
import sys
from pathlib import Path

SCALE = 0.5


def process_with_pillow(device: str, source: Path, target: Path) -> None:
    from PIL import Image

    image = Image.open(source).convert("RGBA")
    # The simulator's screenshots are always portrait; the iPad is used in landscape, so turn it.
    if device == "ipad" and image.width < image.height:
        image = image.rotate(90, expand=True)
    # Rounded Mac window corners are transparent; flatten them onto white.
    flat = Image.new("RGB", image.size, "white")
    flat.paste(image, mask=image.getchannel("A"))
    size = (round(flat.width * SCALE), round(flat.height * SCALE))
    resized = flat.resize(size, Image.LANCZOS)
    resized.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(
        target, optimize=True
    )


def process_with_sips(device: str, source: Path, target: Path) -> None:
    if device == "ipad":
        subprocess.run(
            ["sips", "--rotate", "270", str(source), "--out", str(target)],
            check=True,
            capture_output=True,
        )
        source = target
    report = subprocess.run(
        ["sips", "-g", "pixelWidth", str(source)], check=True, capture_output=True, text=True
    )
    match = re.search(r"pixelWidth: (\d+)", report.stdout)
    width = round(int(match.group(1)) * SCALE) if match else 600
    subprocess.run(
        ["sips", "--resampleWidth", str(width), str(source), "--out", str(target)],
        check=True,
        capture_output=True,
    )


def main() -> int:
    device, raw, output = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    try:
        import PIL  # noqa: F401

        convert = process_with_pillow
    except ImportError:
        convert = process_with_sips
    # Only the captures of this run are replaced; a page's other files stay as they are.
    output.mkdir(parents=True, exist_ok=True)
    count = 0
    for source in sorted(raw.glob("*.png")):
        if source.name.startswith("failed-"):
            continue
        convert(device, source, output / source.name)
        count += 1
    print(f"{device}: {count} screenshots in {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
