#!/usr/bin/env python3
"""Compose the App Store screenshots from the raw app captures.

Design-time helper, like design/icon/make_icon.py. It needs Pillow and NumPy
and is not run by the checks. From the repository root:

    JOURNAL_SCREENSHOT_FONT=/path/to/InterVariable.ttf python3 design/app-store/make_screenshots.py

Inputs are the captures in design/screenshots/raw/ or --raw (see capture-ios.sh,
capture-sync.sh and capture-mac.sh next to this file), the copy in copy.json
and the app icon. Output is docs/app-store/screenshots/{iphone,ipad,mac}/ (or --out),
sRGB JPEGs (quality 94, no chroma subsampling) at the exact App Store sizes in
docs/app-store/screenshots-plan.md, plus a contact sheet when a path is given
with --sheet.

The text is set in Inter (SIL Open Font License), the plan's alternative to
SF Pro. The variable font is not in the repository; point
JOURNAL_SCREENSHOT_FONT at Inter's variable TTF, OTF or WOFF2 file.
"""

from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageCms, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
# Replaced by --raw and --out.
RAW = ROOT / "design" / "screenshots" / "raw"
OUT = ROOT / "docs" / "app-store" / "screenshots"
COPY = json.loads((ROOT / "design" / "app-store" / "copy.json").read_text())
ICON = ROOT / "design" / "icon" / "AppIcon-AppStore-1024.png"

LIGHT = {
    "top": (0xFE, 0xFD, 0xF9),
    "bottom": (0xFD, 0xF3, 0xE9),
    "glow": ((255, 255, 255), 0.45),
    "headline": (0x17, 0x2C, 0x59),
    "subline": (0x58, 0x65, 0x84),
    "accent": (0x17, 0x2C, 0x59),
    "edge": (0x3A, 0x3A, 0x3D),
    "shadow": ((0x17, 0x2C, 0x59), 0.20, 40, 30),
}
DARK = {
    "top": (0x1F, 0x33, 0x5F),
    "bottom": (0x0D, 0x18, 0x34),
    "glow": ((0x2A, 0x43, 0x78), 0.35),
    "headline": (0xF6, 0xF0, 0xE5),
    "subline": (0xBC, 0xBB, 0xBD),
    "accent": (0xF6, 0xF0, 0xE5),
    "edge": (0x4A, 0x4A, 0x4E),
    "shadow": ((0, 0, 0), 0.45, 48, 36),
}
STRONG_SHADOW = DARK["shadow"]
BODY = (0x1B, 0x1B, 0x1D)


@dataclass
class Layout:
    size: tuple[int, int]
    margin: int
    accent: tuple[int, int, int]  # width, height, top
    headline: tuple[int, int, int, int]  # size, line height, top, max lines
    gap: int
    subline: tuple[int, int, int]  # size, line height, max lines
    icon: tuple[int, int, int]  # size, top, headline top


IPHONE = Layout(
    (1320, 2868), 88, (64, 6, 118), (100, 112, 150, 2), 28, (50, 62, 2), (132, 104, 270)
)
IPAD = Layout((2752, 2064), 140, (72, 6, 78), (104, 116, 110, 1), 24, (50, 64, 1), (112, 60, 196))
MAC = Layout((2880, 1800), 160, (72, 6, 70), (96, 108, 100, 1), 22, (46, 60, 1), (104, 56, 180))


# MARK: - Fonts and text


def font_path() -> str:
    path = os.environ.get("JOURNAL_SCREENSHOT_FONT", "")
    if not path or not Path(path).is_file():
        raise SystemExit("Set JOURNAL_SCREENSHOT_FONT to Inter's variable font file.")
    return path


def font(size: int, weight: int, optical: int = 32) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(font_path(), size)
    axes = {axis["name"]: axis for axis in face.get_variation_axes()}
    values = []
    for name, axis in axes.items():
        wanted = weight if name in (b"Weight", "Weight") else optical
        values.append(max(axis["minimum"], min(axis["maximum"], wanted)))
    face.set_variation_by_axes(values)
    return face


def width(face: ImageFont.FreeTypeFont, text: str) -> float:
    return face.getlength(text)


def wrap(face: ImageFont.FreeTypeFont, text: str, limit: float, lines: int) -> list[str]:
    """One line if it fits; otherwise the break that makes the lines closest in width."""
    if width(face, text) <= limit:
        return [text]
    words = text.split()
    best: list[str] | None = None
    if lines >= 2:
        for index in range(1, len(words)):
            first, second = " ".join(words[:index]), " ".join(words[index:])
            if max(width(face, first), width(face, second)) > limit:
                continue
            candidate = [first, second]
            if first.endswith("."):
                # A break between sentences reads best, even when the lines differ more in width.
                return candidate
            if best is None or abs(width(face, first) - width(face, second)) < abs(
                width(face, best[0]) - width(face, best[1])
            ):
                best = candidate
    if best is None:
        raise SystemExit(f"Too long for {lines} line(s): {text}")
    return best


def draw_text(
    canvas: Image.Image,
    layout: Layout,
    frame: str,
    theme: dict,
    with_icon: bool,
    band: tuple[int, int],
) -> int:
    """Draws the accent bar or icon, the headline and the sub-line, centered as one block in
    the band above the device, so the device keeps its place in every frame. Returns the
    bottom of the text."""
    draw = ImageDraw.Draw(canvas)
    w, _ = layout.size
    size, line_height, _, max_lines = layout.headline
    copy = COPY["frames"][frame]
    limit = w - 2 * layout.margin
    headline_font = font(size, 600, 32)
    sub_size, sub_height, sub_lines = layout.subline
    sub_font = font(sub_size, 400, 20)
    headline = wrap(headline_font, copy["headline"], limit, max_lines)
    subline = wrap(sub_font, copy["subline"], limit, sub_lines)
    bar_w, bar_h, bar_top = layout.accent
    icon_size, icon_top, icon_headline = layout.icon
    lead = (
        icon_size + (icon_headline - icon_top - icon_size)
        if with_icon
        else bar_h + (layout.headline[2] - bar_top - bar_h)
    )
    block = lead + len(headline) * line_height + layout.gap + len(subline) * sub_height
    top = band[0] + (band[1] - band[0] - block) // 2
    if with_icon:
        paste_icon(canvas, icon_size, ((w - icon_size) // 2, top))
    else:
        x0 = (w - bar_w) / 2
        rounded(draw, (x0, top, x0 + bar_w, top + bar_h), bar_h / 2, theme["accent"])
    y = top + lead
    for line in headline:
        draw_line(draw, headline_font, line, w, y, line_height, theme["headline"])
        y += line_height
    y += layout.gap
    for line in subline:
        draw_line(draw, sub_font, line, w, y, sub_height, theme["subline"])
        y += sub_height
    return y


def draw_line(draw, face, text, canvas_width, top, line_height, color) -> None:
    """Centers a line in its line box, with the cap height centered like the system does."""
    ascent, descent = face.getmetrics()
    baseline = top + (line_height + ascent - descent) / 2
    draw.text(
        ((canvas_width - width(face, text)) / 2, baseline), text, font=face, fill=color, anchor="ls"
    )


def rounded(draw, box, radius, fill) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill)


# MARK: - Shapes


def rounded_mask(size: tuple[int, int], radius: float, scale: int = 4) -> Image.Image:
    big = Image.new("L", (size[0] * scale, size[1] * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, big.width - 1, big.height - 1), radius=radius * scale, fill=255
    )
    return big.resize(size, Image.Resampling.LANCZOS)


def paste_icon(canvas: Image.Image, size: int, position: tuple[int, int]) -> None:
    icon = Image.open(ICON).convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
    mask = rounded_mask((size, size), size * 0.224)
    shadow_layer(canvas, mask, position, ((0x17, 0x2C, 0x59), 0.18, 10, 6))
    canvas.paste(icon, position, mask)


def background(layout: Layout, theme: dict, center: tuple[float, float]) -> Image.Image:
    w, h = layout.size
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    top = np.array(theme["top"], np.float32)
    bottom = np.array(theme["bottom"], np.float32)
    image = np.broadcast_to(top + (bottom - top) * t, (h, w, 3)).copy()
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    distance = np.hypot(xs - center[0], ys - center[1]) / (0.55 * w)
    glow_color, glow_alpha = theme["glow"]
    alpha = np.clip(1 - distance, 0, 1) ** 1.6 * glow_alpha
    image = image * (1 - alpha[..., None]) + np.array(glow_color, np.float32) * alpha[..., None]
    return Image.fromarray(np.clip(image + 0.5, 0, 255).astype(np.uint8)).convert("RGBA")


def shadow_layer(canvas: Image.Image, alpha: Image.Image, position, shadow) -> None:
    """A soft shadow of an element's shape, tinted and offset downwards, drawn onto the canvas."""
    color, opacity, sigma, offset = shadow
    pad = int(sigma * 3)
    layer = Image.new("L", (alpha.width + 2 * pad, alpha.height + 2 * pad), 0)
    layer.paste(alpha, (pad, pad))
    layer = layer.filter(ImageFilter.GaussianBlur(sigma))
    layer = layer.point(lambda value: int(value * opacity))
    tint = Image.new("RGBA", layer.size, (*color, 255))
    tint.putalpha(layer)
    canvas.alpha_composite(tint, (int(position[0]) - pad, int(position[1]) - pad + offset))


def place(canvas: Image.Image, element: Image.Image, position, shadow) -> None:
    shadow_layer(canvas, element.getchannel("A"), position, shadow)
    canvas.alpha_composite(element, (int(position[0]), int(position[1])))


# MARK: - Devices


def iphone(capture: Image.Image, theme: dict, scale: float = 1.0) -> Image.Image:
    """A generic phone body around the capture: 26 px bezel, Dynamic Island, no buttons."""
    screen_w, screen_h, bezel = round(924 * scale), round(2008 * scale), round(26 * scale)
    screen = capture.convert("RGBA").resize((screen_w, screen_h), Image.Resampling.LANCZOS)
    return device(screen, bezel, 122 * scale, 148 * scale, theme, island=scale)


def ipad(capture: Image.Image, theme: dict, scale: float = 1.0) -> Image.Image:
    screen_w, screen_h, bezel = round(1871 * scale), round(1404 * scale), round(34 * scale)
    screen = capture.convert("RGBA").resize((screen_w, screen_h), Image.Resampling.LANCZOS)
    body = device(screen, bezel, 42 * scale, 76 * scale, theme)
    draw = ImageDraw.Draw(body)
    r = 5 * scale
    cx, cy = body.width / 2, bezel / 2
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(0x2A, 0x2A, 0x2D, 255))
    return body


def device(
    screen, bezel, screen_radius, body_radius, theme, island: float | None = None
) -> Image.Image:
    w, h = screen.width + 2 * bezel, screen.height + 2 * bezel
    body = Image.new("RGBA", (w, h), (*BODY, 255))
    body.putalpha(rounded_mask((w, h), body_radius))
    edge_width = max(2, round(3 * (island or 1)))
    inner = Image.new(
        "RGBA",
        (w - 2 * bezel + 2 * edge_width, h - 2 * bezel + 2 * edge_width),
        (*theme["edge"], 255),
    )
    inner.putalpha(rounded_mask(inner.size, screen_radius + edge_width))
    body.alpha_composite(inner, (bezel - edge_width, bezel - edge_width))
    black = Image.new("RGBA", screen.size, (0, 0, 0, 255))
    black.putalpha(rounded_mask(screen.size, screen_radius))
    body.alpha_composite(black, (bezel, bezel))
    masked = screen.copy()
    masked.putalpha(
        Image.fromarray(
            np.minimum(
                np.asarray(screen.getchannel("A")),
                np.asarray(rounded_mask(screen.size, screen_radius)),
            )
        )
    )
    body.alpha_composite(masked, (bezel, bezel))
    if island:
        pill_w, pill_h = round(250 * island), round(74 * island)
        pill = Image.new("RGBA", (pill_w, pill_h), (0, 0, 0, 255))
        pill.putalpha(rounded_mask((pill_w, pill_h), pill_h / 2))
        body.alpha_composite(pill, ((w - pill_w) // 2, bezel + round(24 * island)))
    return body


# MARK: - Mac windows


def mac_window(name: str, traffic: str = "active") -> Image.Image:
    """A 2x window from the Mac captures.

    On a Retina display the window server's image is already 2x and has everything, so it
    is used as it is. On a 1x display it is combined with the views drawn at 2x (see
    enlarged_window)."""
    server = Image.open(RAW / "mac" / f"{name}-server.png").convert("RGBA")
    views = Image.open(RAW / "mac" / f"{name}-views.png").convert("RGBA")
    base = server if server.size == views.size else enlarged_window(server, views)
    if traffic != "none":
        paint_traffic_lights(base, traffic)
    return base


def enlarged_window(server: Image.Image, views: Image.Image) -> Image.Image:
    """A 2x window from a 1x window server image and the views drawn at 2x.

    The window server's image has everything; the views are sharp but leave out materials:
    the sidebar and the toolbar's glass controls. The sharp views are used below the toolbar
    and right of the sidebar, the enlarged window server image for the rest, with its slight
    tint from what is behind the window matched to the views."""
    reference = np.asarray(server, np.float32)
    small = np.asarray(views.resize(server.size, Image.Resampling.BOX), np.float32)
    h, w = reference.shape[:2]
    # The tint, measured on the right half, where there is never a sidebar.
    right = (reference[h // 4 :, w // 2 :, 3] == 255) & (small[h // 4 :, w // 2 :, 3] == 255)
    tint = np.median(
        (reference[h // 4 :, w // 2 :, :3] - small[h // 4 :, w // 2 :, :3])[right], axis=0
    )
    difference = np.abs(small[..., :3] + tint - reference[..., :3]).max(axis=2)
    # The sidebar: columns from the left that differ almost everywhere.
    columns = np.median(difference[h // 4 : h - 20], axis=0) > 4
    left = 0
    while left < w // 3 and (columns[left] or left < 4):
        left += 1
    # The toolbar: rows at the top where the glass controls are missing from the views.
    rows = (difference[:, left + 4 : w - 4] > 60).mean(axis=1) > 0.01
    top = 0
    for y in range(min(130, h)):
        if rows[y]:
            top = y + 3
    region = np.zeros((h, w), bool)
    region[top:, left:] = True
    region &= (reference[..., 3] == 255) & (small[..., 3] == 255)
    offset = (
        np.median((reference[..., :3] - small[..., :3])[region], axis=0)
        if region.any()
        else np.zeros(3)
    )
    matched = reference.copy()
    matched[:, left:, :3] = np.clip(matched[:, left:, :3] - offset, 0, 255)
    base = Image.fromarray(matched.astype(np.uint8)).resize(
        (w * 2, h * 2), Image.Resampling.LANCZOS
    )
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).rectangle((left * 2 + 2, top * 2 + 2, w * 2, h * 2), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    sharp = views.copy()
    sharp.putalpha(Image.fromarray(np.minimum(np.asarray(mask), np.asarray(views.getchannel("A")))))
    base.alpha_composite(sharp)
    base.putalpha(server.getchannel("A").resize(base.size, Image.Resampling.LANCZOS))
    return base


def paint_traffic_lights(window: Image.Image, mode: str) -> None:
    """The captures show the window as inactive; draws the buttons as in the frontmost window."""
    pixels = np.asarray(window.convert("RGB"), np.int32)
    region = pixels[20:80, 20:180]
    backdrop = np.median(region.reshape(-1, 3), axis=0)
    marked = np.abs(region - backdrop).max(axis=2) > 18
    columns = np.where(marked.any(axis=0))[0]
    if len(columns) == 0:
        return
    groups: list[list[int]] = [[int(columns[0])]]
    for column in columns[1:]:
        if column - groups[-1][-1] > 3:
            groups.append([])
        groups[-1].append(int(column))
    circles = [group for group in groups if 20 <= len(group) <= 34][:3]
    rows = np.where(marked.any(axis=1))[0]
    cy = 20 + (rows.min() + rows.max()) / 2
    colors = [(0xFF, 0x5F, 0x57), (0xFE, 0xBC, 0x2E), (0x28, 0xC8, 0x40)]
    draw = ImageDraw.Draw(window)
    for index, group in enumerate(circles):
        if mode == "close" and index > 0:
            break
        cx = 20 + (group[0] + group[-1]) / 2
        r = (group[-1] - group[0] + 1) / 2
        big = Image.new("RGBA", (int(r * 8) + 8, int(r * 8) + 8), (0, 0, 0, 0))
        ImageDraw.Draw(big).ellipse(
            (4, 4, 4 + r * 8, 4 + r * 8), fill=(*colors[index], 255), outline=(0, 0, 0, 40), width=3
        )
        small = big.resize((int(r * 2) + 2, int(r * 2) + 2), Image.Resampling.LANCZOS)
        window.alpha_composite(small, (int(round(cx - r - 1)), int(round(cy - r - 1))))
    del draw


def scaled(image: Image.Image, factor: float) -> Image.Image:
    return image.resize(
        (round(image.width * factor), round(image.height * factor)), Image.Resampling.LANCZOS
    )


# MARK: - Frames


def raw(platform: str, name: str) -> Image.Image:
    image = Image.open(RAW / platform / f"{name}.png").convert("RGBA")
    if platform == "ipad" and image.width < image.height:
        image = image.rotate(90, expand=True)
    return image


def save(canvas: Image.Image, platform: str, name: str) -> Path:
    folder = OUT / platform
    folder.mkdir(parents=True, exist_ok=True)
    # JPEG at quality 94 without chroma subsampling looks the same as PNG, and keeps the frames with
    # photos small enough for the repository.
    path = folder / f"{name}.jpg"
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    canvas.convert("RGB").save(
        path, quality=94, subsampling=0, optimize=True, progressive=False, icc_profile=profile
    )
    return path


def phone_frame(number: str, capture: str, dark: bool = False) -> Image.Image:
    layout, theme = IPHONE, DARK if dark else LIGHT
    body = iphone(raw("iphone", capture), theme)
    x, y = (layout.size[0] - body.width) / 2, 700
    canvas = background(layout, theme, (x + body.width / 2, y + body.height / 2))
    draw_text(canvas, layout, number, theme, number == "01", (70, y - 50))
    place(canvas, body, (x, y), theme["shadow"])
    return canvas


def pad_frame(number: str, capture: str, dark: bool = False) -> Image.Image:
    layout, theme = IPAD, DARK if dark else LIGHT
    body = ipad(raw("ipad", capture), theme)
    x, y = (layout.size[0] - body.width) / 2, 470
    canvas = background(layout, theme, (x + body.width / 2, y + body.height / 2))
    draw_text(canvas, layout, number, theme, number == "01", (40, y - 36))
    place(canvas, body, (x, y), theme["shadow"])
    return canvas


def mac_single(number: str, window: Image.Image, dark: bool = False) -> Image.Image:
    layout, theme = MAC, DARK if dark else LIGHT
    element = scaled(window, 0.82)
    x, y = (layout.size[0] - element.width) / 2, 400
    canvas = background(layout, theme, (x + element.width / 2, y + element.height / 2))
    draw_text(canvas, layout, number, theme, number == "01", (36, y - 36))
    place(canvas, element, (x, y), theme["shadow"])
    return canvas


def mac_with_settings(
    number,
    main,
    front,
    dark=False,
    main_at=(240, 430),
    front_corner=(2640, 1730),
    extra=None,
    front_height=None,
):
    """The main window with a window or page in front, its bottom right corner at front_corner.

    A front element taller than front_height at the usual scale is scaled down to that height."""
    layout, theme = MAC, DARK if dark else LIGHT
    back = scaled(main, 0.70)
    element = scaled(front, 0.82)
    if front_height and element.height > front_height:
        element = scaled(front, front_height / front.height)
    canvas = background(layout, theme, (layout.size[0] / 2, 1100))
    draw_text(canvas, layout, number, theme, False, (36, main_at[1] - 36))
    place(canvas, back, main_at, theme["shadow"])
    place(
        canvas,
        element,
        (front_corner[0] - element.width, front_corner[1] - element.height),
        STRONG_SHADOW,
    )
    if extra:
        extra(canvas, theme)
    return canvas


def attach_sheet(window: Image.Image, sheet: Image.Image) -> Image.Image:
    """Shows a sheet where macOS attaches it: centered below the toolbar."""
    combined = window.copy()
    x = (window.width - sheet.width) // 2
    y = 52 * 2
    shadow_layer(combined, sheet.getchannel("A"), (x, y), ((0, 0, 0), 0.30, 18, 8))
    combined.alpha_composite(sheet, (x, y))
    return combined


def agent_card(canvas: Image.Image, theme: dict) -> None:
    """The agent's shortened answer over the lower left of the main window, bottom at y 1710."""
    agent = COPY["agent"]
    w, x, bottom, pad = 980, 200, 1710, 40
    caption = font(26, 600, 20)
    question = font(34, 600, 28)
    answer = font(32, 400, 20)
    questions = greedy(question, agent["question"], w - 2 * pad)
    answers = greedy(answer, agent["answer"], w - 2 * pad)
    if len(answers) > 4:
        raise SystemExit("The agent's answer needs more than 4 lines.")
    h = pad + 36 + 12 + len(questions) * 46 + 18 + len(answers) * 46 + pad - 6
    card = Image.new("RGBA", (w, h), (0xFB, 0xF7, 0xF0, 255))
    card.putalpha(rounded_mask((w, h), 28))
    draw = ImageDraw.Draw(card)
    top = pad
    draw.text((pad, top), agent["caption"], font=caption, fill=(0x58, 0x65, 0x84), anchor="la")
    top += 48
    for line in questions:
        draw.text((pad, top), line, font=question, fill=(0x17, 0x2C, 0x59), anchor="la")
        top += 46
    top += 18
    for line in answers:
        draw.text((pad, top), line, font=answer, fill=(0x17, 0x2C, 0x59), anchor="la")
        top += 46
    place(canvas, card, (x, bottom - h), STRONG_SHADOW)


def greedy(face, text, limit) -> list[str]:
    lines: list[str] = []
    for word in text.split():
        if lines and width(face, lines[-1] + " " + word) <= limit:
            lines[-1] += " " + word
        else:
            lines.append(word)
    return lines


def build() -> dict[str, list[Path]]:
    outputs: dict[str, list[Path]] = {"iphone": [], "ipad": [], "mac": []}
    phone = [
        ("01", "01-writing-light", "01-hero", False),
        ("02", "02-privacy-light", "02-privacy", False),
        ("03", "03-devices-light", "03-sync", False),
        ("04", "04-pinned-light", "04-find", False),
        ("05", "05-journals-list", "05-journals", False),
        ("06", "06-dark", "06-dark", True),
        ("07", "07-backup-light", "07-markdown", False),
    ]
    for number, capture, name, dark in phone:
        outputs["iphone"].append(save(phone_frame(number, capture, dark), "iphone", name))
    tablet = [
        ("01", "01-writing-light", "01-hero", False),
        ("02", "02-privacy-light", "02-privacy", False),
        ("03", "03-pairing-light", "03-sync", False),
        ("04", "04-history-light", "04-find", False),
        ("05", "05-journals-light", "05-journals", False),
        ("06", "06-dark", "06-dark", True),
        ("07", "07-backup-light", "07-markdown", False),
    ]
    for number, capture, name, dark in tablet:
        outputs["ipad"].append(save(pad_frame(number, capture, dark), "ipad", name))

    main_light = mac_window("01-main-light")
    outputs["mac"].append(save(mac_single("01", main_light), "mac", "01-hero"))
    inactive = mac_window("01-main-light", traffic="none")
    privacy = mac_window("02-settings-privacy-light", traffic="close")
    outputs["mac"].append(save(mac_with_settings("02", inactive, privacy), "mac", "02-privacy"))

    phone_list = raw("iphone", "03-personal-list-light")

    def add_phone(canvas: Image.Image, theme: dict) -> None:
        body = iphone(phone_list, theme, 0.52)
        place(canvas, body, (2250, 640), STRONG_SHADOW)

    sync = mac_window("03-settings-sync-light", traffic="close")
    outputs["mac"].append(
        save(
            mac_with_settings(
                "03", inactive, sync, main_at=(200, 430), front_corner=(2180, 1730), extra=add_phone
            ),
            "mac",
            "03-sync",
        )
    )
    # The agent's page is a sheet of Settings, without a title bar. It takes the place of the
    # Agent Access pane of the 2026-09-28 set, at most as tall (877 px, top at y 843).
    agent_page = mac_window("04-agent-detail-dark", traffic="none")
    main_dark = mac_window("04-main-dark", traffic="none")
    four = mac_with_settings(
        "04-mac",
        main_dark,
        agent_page,
        True,
        (200, 430),
        (2680, 1720),
        agent_card,
        front_height=877,
    )
    outputs["mac"].append(save(four, "mac", "04-insights"))
    sheet = mac_window("05-sheet-light", traffic="none")
    offsite = attach_sheet(mac_window("05-main-light"), sheet)
    outputs["mac"].append(save(mac_single("05", offsite), "mac", "05-journals"))

    layout, theme = MAC, DARK
    canvas = background(layout, theme, (layout.size[0] / 2, 1100))
    draw_text(canvas, layout, "06", theme, False, (36, 420 - 36))
    window = scaled(mac_window("06-main-dark"), 0.66)
    place(canvas, window, (595, 420), theme["shadow"])
    tablet_body = ipad(raw("ipad", "06-dark"), theme, 0.42)
    place(canvas, tablet_body, (1880, 1080), STRONG_SHADOW)
    phone_body = iphone(raw("iphone", "06-dark"), theme, 0.40)
    place(canvas, phone_body, (330, 900), STRONG_SHADOW)
    outputs["mac"].append(save(canvas, "mac", "06-dark"))
    backup = mac_window("07-settings-backup-light", traffic="close")
    outputs["mac"].append(save(mac_with_settings("07", inactive, backup), "mac", "07-markdown"))
    return outputs


def check(outputs: dict[str, list[Path]]) -> None:
    sizes = {"iphone": IPHONE.size, "ipad": IPAD.size, "mac": MAC.size}
    for platform, paths in outputs.items():
        for path in paths:
            with Image.open(path) as image:
                if image.size != sizes[platform] or image.mode != "RGB":
                    raise SystemExit(f"{path}: {image.size} {image.mode}")


def contact_sheet(outputs: dict[str, list[Path]], path: Path) -> None:
    rows = []
    for platform, height in (("iphone", 700), ("ipad", 460), ("mac", 400)):
        images = [Image.open(p).convert("RGB") for p in outputs[platform]]
        images = [
            i.resize((round(i.width * height / i.height), height), Image.Resampling.LANCZOS)
            for i in images
        ]
        row_width = sum(i.width for i in images) + 24 * (len(images) - 1)
        row = Image.new("RGB", (row_width, height), (236, 232, 224))
        x = 0
        for image in images:
            row.paste(image, (x, 0))
            x += image.width + 24
        rows.append(row)
    sheet_width = max(r.width for r in rows) + 96
    sheet = Image.new(
        "RGB", (sheet_width, sum(r.height for r in rows) + 48 * (len(rows) + 1)), (236, 232, 224)
    )
    y = 48
    for row in rows:
        sheet.paste(row, ((sheet_width - row.width) // 2, y))
        y += row.height + 48
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, optimize=True)


def main() -> None:
    global RAW, OUT
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sheet", type=Path, help="also write a contact sheet of every frame here")
    parser.add_argument("--raw", type=Path, help=f"the captures (default {RAW.relative_to(ROOT)})")
    parser.add_argument("--out", type=Path, help=f"the output folder (default {OUT.relative_to(ROOT)})")
    arguments = parser.parse_args()
    RAW = (arguments.raw or RAW).resolve()
    OUT = (arguments.out or OUT).resolve()
    outputs = build()
    check(outputs)
    if arguments.sheet:
        contact_sheet(outputs, arguments.sheet)
    for paths in outputs.values():
        for path in paths:
            print("wrote", path)


if __name__ == "__main__":
    main()
