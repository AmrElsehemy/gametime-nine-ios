#!/usr/bin/env python3
"""Compose final 13-inch iPad (12.9-inch slot) App Store masters from real simulator captures."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "Marketing" / "Capture" / "raw-ipad"
OUT = ROOT / "Marketing" / "AppStore" / "Screenshots-iPad"
TARGET = (2048, 2732)
CARD_WIDTH = 1900
CARD_TOP = 430
STATUS_CROP = 100  # raw px (at capture width) covering the iPad status bar

# Raw-frame row ranges that hold only empty app background. They are cut out so the
# board and controls sit closer together and the device reads larger in the thumbnail.
HEADER_GAP = (380, 790)
BOTTOM_GAP = (1800, 2200)
RESULT_GAP = (1800, 2200)
# The iPad layout leaves wide empty margins; keep only the columns holding the board and
# controls (this also drops the stray loading arc in the capture's bottom-right corner).
CROP_X = (280, 1784)

# (raw capture, output file, headline, supporting line). The first three slides are
# the ones shown in search results, so they carry the goal, the daily hook and the payoff.
COPY = [
    ("01-simple.png", "01-solve.png", "Solve the Logic Grid", "One per row, column and territory.", [HEADER_GAP, BOTTOM_GAP]),
    ("04-daily.png", "02-daily.png", "A New Puzzle Every Day", "Build your streak. One missed day is forgiven.", [HEADER_GAP, BOTTOM_GAP]),
    ("05-solved.png", "03-solved.png", "Chase Three Stars", "Every board has exactly one solution.", [HEADER_GAP, RESULT_GAP]),
    ("03-territories.png", "04-boards.png", "100 Boards, All Solvable", "Solver-verified, from gentle to demanding.", [HEADER_GAP, BOTTOM_GAP]),
    ("02-placement.png", "05-placement.png", "Tap, Think Ahead, Place", "Undo, reset, or ask for a hint.", [HEADER_GAP, BOTTOM_GAP]),
]


def font(size: int, bold: bool = False):
    candidates = [
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size, index=0)
        except Exception:
            pass
    return ImageFont.load_default()


def cover(image: Image.Image, target: tuple[int, int]) -> Image.Image:
    tw, th = target
    target_ratio = tw / th
    ratio = image.width / image.height
    if ratio > target_ratio:
        nh = th
        nw = round(nh * ratio)
    else:
        nw = tw
        nh = round(nw / ratio)
    image = image.resize((nw, nh), Image.Resampling.LANCZOS)
    left = max(0, (nw - tw) // 2)
    top = max(0, (nh - th) // 2)
    return image.crop((left, top, left + tw, top + th))


def centered_multiline(
    draw,
    text: str,
    y: int,
    fnt,
    fill,
    max_width: int,
    spacing: int = 10,
    stroke_width: int = 2,
):
    words = text.split()
    lines, current = [], []
    for word in words:
        trial = " ".join(current + [word])
        box = draw.textbbox((0, 0), trial, font=fnt, stroke_width=stroke_width)
        if box[2] - box[0] <= max_width or not current:
            current.append(word)
        else:
            lines.append(" ".join(current))
            current = [word]
    if current:
        lines.append(" ".join(current))
    for line in lines:
        box = draw.textbbox((0, 0), line, font=fnt, stroke_width=stroke_width)
        width = box[2] - box[0]
        draw.text(
            ((TARGET[0] - width) / 2, y),
            line,
            font=fnt,
            fill=fill,
            stroke_width=stroke_width,
            stroke_fill=(0, 0, 0, 150),
        )
        y += (box[3] - box[1]) + spacing
    return y


def cut_bands(raw: Image.Image, bands) -> Image.Image:
    """Remove empty horizontal bands (raw-frame rows), highest first so offsets stay valid."""
    for start, end in sorted(bands, reverse=True):
        top = raw.crop((0, 0, raw.width, start))
        bottom = raw.crop((0, end, raw.width, raw.height))
        raw = Image.new("RGB", (raw.width, top.height + bottom.height))
        raw.paste(top, (0, 0))
        raw.paste(bottom, (0, top.height))
    return raw


def rounded_card(raw: Image.Image) -> Image.Image:
    raw = raw.crop((0, STATUS_CROP, raw.width, raw.height))
    scale = CARD_WIDTH / raw.width
    card = raw.resize((CARD_WIDTH, round(raw.height * scale)), Image.Resampling.LANCZOS).convert("RGBA")
    max_h = TARGET[1] - CARD_TOP
    if card.height > max_h:
        card = card.crop((0, 0, card.width, max_h))

    # Only the top corners are rounded: the card bleeds off the bottom edge.
    mask = Image.new("L", card.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, card.width - 1, card.height + 200), radius=80, fill=255)
    card.putalpha(mask)
    return card


def compose(raw_path: Path, out_path: Path, title: str, subtitle: str, bands) -> None:
    raw = Image.open(raw_path).convert("RGB")
    raw = raw.crop((CROP_X[0], 0, CROP_X[1], raw.height))
    raw = cut_bands(raw, bands)

    # Real gameplay remains the visual source: a blurred/darkened copy becomes the
    # surrounding atmosphere and an unmodified clean capture sits in front.
    backdrop = cover(raw, TARGET).filter(ImageFilter.GaussianBlur(48))
    backdrop = ImageEnhance.Brightness(backdrop).enhance(0.30).convert("RGBA")
    tint = Image.new("RGBA", TARGET, (8, 17, 18, 132))
    canvas = Image.alpha_composite(backdrop, tint)

    card = rounded_card(raw)
    x = (TARGET[0] - card.width) // 2

    shadow = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    shadow_shape = Image.new("L", card.size, 0)
    ImageDraw.Draw(shadow_shape).rounded_rectangle((0, 0, card.width - 1, card.height - 1), radius=80, fill=190)
    shadow_shape = shadow_shape.filter(ImageFilter.GaussianBlur(30))
    shadow_layer = Image.new("RGBA", card.size, (0, 0, 0, 0))
    shadow_layer.putalpha(shadow_shape)
    shadow.alpha_composite(shadow_layer, (x, CARD_TOP + 22))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(card, (x, CARD_TOP))

    draw = ImageDraw.Draw(canvas)
    title_font = font(124, bold=True)
    subtitle_font = font(60, bold=False)
    next_y = centered_multiline(draw, title, 100, title_font, (255, 255, 255, 255), 1850, 10)
    centered_multiline(draw, subtitle, next_y + 50, subtitle_font, (232, 238, 234, 235), 1800, 8)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for raw_name, out_name, title, subtitle, bands in COPY:
        raw_path = RAW / raw_name
        if not raw_path.exists():
            raise SystemExit(f"Missing raw capture: {raw_path}")
        compose(raw_path, OUT / out_name, title, subtitle, bands)
    print("Composed five 2048x2732 App Store screenshot masters")


if __name__ == "__main__":
    main()
