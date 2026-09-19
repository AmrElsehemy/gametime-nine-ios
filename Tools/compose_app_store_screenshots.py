#!/usr/bin/env python3
"""Compose final 6.9-inch App Store masters from real simulator captures."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "Marketing" / "Capture" / "raw"
OUT = ROOT / "Marketing" / "AppStore" / "Screenshots"
TARGET = (1320, 2868)
CARD_WIDTH = 980
CARD_TOP = 630

COPY = {
    "01-simple.png": ("A Surprisingly Simple Idea", "One Pebble in every row, column, and territory."),
    "02-placement.png": ("Place the Pebbles", "Tap a cell. Think ahead. Feel every move."),
    "03-territories.png": ("Master Irregular Territories", "Every board is different. Every solution is unique."),
    "04-daily.png": ("Daily Puzzles", "A fresh challenge every day. Keep your streak alive."),
    "05-solved.png": ("That Satisfying Solved Moment", "Clear. Calm. Complete."),
}


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


def centered_multiline(draw, text: str, y: int, fnt, fill, max_width: int, spacing: int = 10):
    words = text.split()
    lines, current = [], []
    for word in words:
        trial = " ".join(current + [word])
        box = draw.textbbox((0, 0), trial, font=fnt)
        if box[2] - box[0] <= max_width or not current:
            current.append(word)
        else:
            lines.append(" ".join(current))
            current = [word]
    if current:
        lines.append(" ".join(current))
    for line in lines:
        box = draw.textbbox((0, 0), line, font=fnt)
        width = box[2] - box[0]
        draw.text(((TARGET[0] - width) / 2, y), line, font=fnt, fill=fill)
        y += (box[3] - box[1]) + spacing
    return y


def rounded_card(raw: Image.Image) -> Image.Image:
    scale = CARD_WIDTH / raw.width
    card = raw.resize((CARD_WIDTH, round(raw.height * scale)), Image.Resampling.LANCZOS).convert("RGBA")
    max_h = TARGET[1] - CARD_TOP - 68
    if card.height > max_h:
        card = card.crop((0, 0, card.width, max_h))

    mask = Image.new("L", card.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, card.width - 1, card.height - 1), radius=64, fill=255)
    card.putalpha(mask)
    return card


def compose(raw_path: Path, out_path: Path, title: str, subtitle: str) -> None:
    raw = Image.open(raw_path).convert("RGB")

    # Real gameplay remains the visual source: a blurred/darkened copy becomes the
    # surrounding atmosphere and an unmodified clean capture sits in front.
    backdrop = cover(raw, TARGET).filter(ImageFilter.GaussianBlur(36))
    backdrop = ImageEnhance.Brightness(backdrop).enhance(0.30).convert("RGBA")
    tint = Image.new("RGBA", TARGET, (8, 17, 18, 132))
    canvas = Image.alpha_composite(backdrop, tint)

    card = rounded_card(raw)
    x = (TARGET[0] - card.width) // 2

    shadow = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    shadow_shape = Image.new("L", card.size, 0)
    ImageDraw.Draw(shadow_shape).rounded_rectangle((0, 0, card.width - 1, card.height - 1), radius=64, fill=190)
    shadow_shape = shadow_shape.filter(ImageFilter.GaussianBlur(30))
    shadow_layer = Image.new("RGBA", card.size, (0, 0, 0, 0))
    shadow_layer.putalpha(shadow_shape)
    shadow.alpha_composite(shadow_layer, (x, CARD_TOP + 22))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(card, (x, CARD_TOP))

    draw = ImageDraw.Draw(canvas)
    brand_font = font(30, bold=True)
    brand = "NINE   ·   KNOWLLY GAMES"
    b = draw.textbbox((0, 0), brand, font=brand_font)
    draw.text(((TARGET[0] - (b[2] - b[0])) / 2, 66), brand, font=brand_font, fill=(151, 205, 194, 220))

    title_font = font(78, bold=True)
    subtitle_font = font(38, bold=False)
    next_y = centered_multiline(draw, title, 142, title_font, (255, 255, 255, 255), 1120, 8)
    centered_multiline(draw, subtitle, next_y + 28, subtitle_font, (232, 238, 234, 235), 1040, 7)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for filename, (title, subtitle) in COPY.items():
        raw_path = RAW / filename
        if not raw_path.exists():
            raise SystemExit(f"Missing raw capture: {raw_path}")
        compose(raw_path, OUT / filename, title, subtitle)
    print("Composed five 1320x2868 App Store screenshot masters")


if __name__ == "__main__":
    main()
