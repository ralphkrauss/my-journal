#!/usr/bin/env python3
"""Rebuild the My Journal app icon from the chosen artwork.

Design-time helper. It needs Pillow and NumPy, which are not part of the pinned
toolchain, and is not run by the checks. From the repository root:

    python3 design/icon/make_icon.py

It separates the handwritten lettering in design/icon/source/chosen-artwork.png
from its paper background, replaces the slightly noisy paper with a clean
two-colour gradient, and writes the layer PNGs, flattened appearance references,
the App Store export and the Icon Composer bundle used by the Xcode targets.
"""

from __future__ import annotations

import json
import shutil
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageCms, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / "design" / "icon"
SOURCE = DESIGN / "source" / "chosen-artwork.png"
LAYERS = DESIGN / "layers"
FLATTENED = DESIGN / "flattened"
APP_STORE = DESIGN / "AppIcon-AppStore-1024.png"
ICON_BUNDLE = ROOT / "apps" / "apple" / "JournalApp" / "Resources" / "AppIcon.icon"
SIZE = 1024

# Dark appearance: deep navy paper with paper-white ink (sRGB, 0-255).
DARK_TOP = (31, 51, 95)
DARK_BOTTOM = (13, 24, 52)
PAPER_WHITE = (246, 240, 229)
WHITE = (255, 255, 255)

# Pixels darker than this (mean of R, G, B) are certainly ink; pixels darker
# than the core value are the stroke interiors that define the ink colour.
INK_LUMINANCE = 200
INK_CORE_LUMINANCE = 70
# The paper gradient is fitted to pixels at least this far from any stroke.
PAPER_MARGIN = 7
# Anti-aliased edges are one or two pixels wide; anything farther from the
# strokes than this is paper, whatever its value.
EDGE_REACH = 4
# Paper grain reaches about 0.015 alpha. Coverage below the floor becomes
# transparent and coverage above the ceiling opaque, which removes the grain on
# the paper and inside the strokes but keeps the anti-aliased edges.
ALPHA_FLOOR = 0.04
ALPHA_CEILING = 0.95
# Icon Composer (Xcode 26.6) paints the icon background gradient from top to
# bottom, starting at 10% and ending at 90% of the height, and ignores an
# orientation on the background fill (measured with ictool).
GRADIENT_TOP = 0.1
GRADIENT_BOTTOM = 0.9


def load_source() -> np.ndarray:
    image = Image.open(SOURCE).convert("RGB")
    if image.size != (SIZE, SIZE):
        raise SystemExit(f"{SOURCE} must be {SIZE}x{SIZE} pixels.")
    return np.asarray(image).astype(np.float64)


def near_ink(pixels: np.ndarray, reach: int) -> np.ndarray:
    ink = (pixels.mean(axis=2) < INK_LUMINANCE).astype(np.uint8) * 255
    grown = Image.fromarray(ink).filter(ImageFilter.MaxFilter(2 * reach + 1))
    return np.asarray(grown) > 0


def unit_grid() -> tuple[np.ndarray, np.ndarray]:
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    return (xs + 0.5) / SIZE, (ys + 0.5) / SIZE


def paper_surface(pixels: np.ndarray, paper: np.ndarray) -> np.ndarray:
    """Smooth quadratic estimate of the paper colour under every pixel."""
    x, y = unit_grid()
    terms = np.stack([np.ones_like(x), x, y, x * x, y * y, x * y], axis=-1)
    coefficients, *_ = np.linalg.lstsq(terms[paper], pixels[paper], rcond=None)
    return terms @ coefficients


def ink_colour(pixels: np.ndarray) -> np.ndarray:
    core = pixels.mean(axis=2) < INK_CORE_LUMINANCE
    return np.round(np.median(pixels[core], axis=0))


def lettering_alpha(pixels: np.ndarray, surface: np.ndarray, ink: np.ndarray) -> np.ndarray:
    """Coverage of each pixel by ink, assuming pixel = paper * (1 - a) + ink * a."""
    towards_ink = ink - surface
    coverage = ((pixels - surface) * towards_ink).sum(axis=2) / (towards_ink**2).sum(axis=2)
    coverage = np.where(near_ink(pixels, EDGE_REACH), coverage, 0.0)
    coverage = (coverage - ALPHA_FLOOR) / (ALPHA_CEILING - ALPHA_FLOOR)
    return np.clip(coverage, 0.0, 1.0)


def gradient_ramp() -> np.ndarray:
    _, y = unit_grid()
    return np.clip((y - GRADIENT_TOP) / (GRADIENT_BOTTOM - GRADIENT_TOP), 0.0, 1.0)


def fit_paper_gradient(pixels: np.ndarray, paper: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Top and bottom colours of the Icon Composer gradient closest to the paper."""
    ramp = gradient_ramp()[paper]
    basis = np.stack([1.0 - ramp, ramp], axis=1)
    colours, *_ = np.linalg.lstsq(basis, pixels[paper], rcond=None)
    top, bottom = np.clip(np.round(colours), 0, 255)
    return top, bottom


def render_gradient(top, bottom) -> np.ndarray:
    ramp = gradient_ramp()[..., None]
    return np.asarray(top, dtype=np.float64) * (1.0 - ramp) + np.asarray(bottom) * ramp


def composite(background: np.ndarray, colour, alpha: np.ndarray) -> np.ndarray:
    coverage = alpha[..., None]
    return background * (1.0 - coverage) + np.asarray(colour, dtype=np.float64) * coverage


def to_image(values: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(np.round(values), 0, 255).astype(np.uint8))


def srgb_profile() -> bytes:
    profile = bytearray(ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes())
    # The header records when the profile was created; a fixed date keeps
    # regenerated PNGs byte-identical.
    profile[24:36] = struct.pack(">6H", 2026, 9, 27, 0, 0, 0)
    return bytes(profile)


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    options = {"optimize": True}
    if image.mode != "L":
        options["icc_profile"] = srgb_profile()
    image.save(path, **options)


def colour_string(colour) -> str:
    red, green, blue = (float(channel) / 255.0 for channel in colour)
    return f"srgb:{red:.5f},{green:.5f},{blue:.5f},1.00000"


def icon_document(paper_top, paper_bottom) -> dict:
    light = [colour_string(paper_top), colour_string(paper_bottom)]
    dark = [colour_string(DARK_TOP), colour_string(DARK_BOTTOM)]
    return {
        "fill-specializations": [
            {"value": {"linear-gradient": light}},
            {"appearance": "dark", "value": {"linear-gradient": dark}},
        ],
        "groups": [
            {
                "name": "Lettering",
                "layers": [
                    {
                        "name": "Lettering",
                        "image-name": "lettering.png",
                        "glass": False,
                        # The navy ink would almost vanish in the clear and
                        # tinted appearances, which use the layer's lightness.
                        "fill-specializations": [
                            {"appearance": "dark", "value": {"solid": colour_string(PAPER_WHITE)}},
                            {"appearance": "tinted", "value": {"solid": colour_string(WHITE)}},
                        ],
                    }
                ],
                # No Liquid Glass effects: the lettering stays flat ink on paper.
                "shadow": {"kind": "none", "opacity": 0.5},
                "specular": False,
                "translucency": {"enabled": False, "value": 0.5},
            }
        ],
        "supported-platforms": {"squares": "shared"},
    }


def write_icon_bundle(lettering: Image.Image, paper_top, paper_bottom) -> None:
    if ICON_BUNDLE.exists():
        shutil.rmtree(ICON_BUNDLE)
    save(lettering, ICON_BUNDLE / "Assets" / "lettering.png")
    document = json.dumps(icon_document(paper_top, paper_bottom), indent=2) + "\n"
    (ICON_BUNDLE / "icon.json").write_text(document, encoding="utf-8")


def main() -> None:
    pixels = load_source()
    paper = ~near_ink(pixels, PAPER_MARGIN)
    ink = ink_colour(pixels)
    alpha = lettering_alpha(pixels, paper_surface(pixels, paper), ink)
    paper_top, paper_bottom = fit_paper_gradient(pixels, paper)
    light_paper = render_gradient(paper_top, paper_bottom)
    dark_paper = render_gradient(DARK_TOP, DARK_BOTTOM)

    lettering = np.zeros((SIZE, SIZE, 4))
    lettering[..., :3] = ink
    lettering[..., 3] = alpha * 255.0
    lettering_image = to_image(lettering)
    light_icon = to_image(composite(light_paper, ink, alpha))

    save(lettering_image, LAYERS / "lettering.png")
    save(to_image(light_paper), LAYERS / "background-light.png")
    save(to_image(dark_paper), LAYERS / "background-dark.png")
    save(light_icon, FLATTENED / "AppIcon-light.png")
    save(to_image(composite(dark_paper, PAPER_WHITE, alpha)), FLATTENED / "AppIcon-dark.png")
    save(to_image(alpha * 255.0), FLATTENED / "AppIcon-tinted.png")
    save(light_icon, APP_STORE)
    write_icon_bundle(lettering_image, paper_top, paper_bottom)

    difference = np.abs(np.asarray(light_icon).astype(np.float64) - pixels)
    print(f"ink colour: {tuple(int(channel) for channel in ink)}")
    print(f"paper top: {tuple(map(int, paper_top))}, bottom: {tuple(map(int, paper_bottom))}")
    print(f"difference from source: mean {difference.mean():.2f}, max {difference.max():.0f}")


if __name__ == "__main__":
    main()
