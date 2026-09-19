#!/usr/bin/env python3
"""Compose final App Store screenshot masters from real simulator captures."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "Marketing" / "Capture" / "raw"
OUT = ROOT / "Marketing" / "AppStore" / "Screenshots"
TARGET = (1320, 2868)

COPY = {
    "01-simple.png": ("A Surprisingly Simple Idea", "One Pebble in every row, column, and territory."),
    "02-placement.png": ("Place the Pebbles", "Tap a cell. Think ahead. Feel every move."),
    "03-territories.png": ("Master Irregular Territories", "Every board is different. Every solution is unique."),
    "04-daily.png": ("Daily Puzzles", "A fresh challenge every day. Keep your streak alive."),
    "05-solved.png": ("That Satisfying Solved Moment", "Clear. Calm. Complete."),
}


def font(size: int, bold: bool = False):
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size, index=0)
        except Exception:
            pass
    return ImageFont.load_default()


def fit_cover(image: Image.Image) -> Image.Image:
    target_ratio = TARGET[0] / TARGET[1]
    ratio = image.width / image.height
    if ratio > target_ratio:
        new_h = TARGET[1]
        new_w = round(new_h * ratio)
    else:
        new_w = TARGET[0]
        new_h = round(new_w / ratio)
    image = image.resize((new_w, new_h), Image.Resampling.LANCZOS)
    left = max(0, (new_w - TARGET[0]) // 2)
    top = max(0, (new_h - TARGET[1]) // 2)
    return image.crop((left, top, left + TARGET[0], top + TARGET[1]))


def centered_multiline(draw: ImageDraw.ImageDraw, text: str, y: int, fnt, fill, max_width: int, spacing: int = 8):
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
        box = draw.textbbox((0, 0), line, font=fnt, stroke_width=2)
        width = box[2] - box[0]
        draw.text(((TARGET[0] - width) / 2, y), line, font=fnt, fill=fill,
                  stroke_width=2, stroke_fill=(0, 0, 0, 110))
        y += (box[3] - box[1]) + spacing
    return y


def compose(raw_path: Path, out_path: Path, title: str, subtitle: str) -> None:
    image = fit_cover(Image.open(raw_path).convert("RGB")).convert("RGBA")

    # Dark top fade leaves the real gameplay visible while giving the copy a clean stage.
    overlay = Image.new("RGBA", TARGET, (0, 0, 0, 0))
    opx = overlay.load()
    for y in range(760):
        alpha = int(205 * (1 - y / 760) ** 1.7)
        for x in range(TARGET[0]):
            opx[x, y] = (10, 15, 16, alpha)
    image = Image.alpha_composite(image, overlay)

    draw = ImageDraw.Draw(image)
    title_font = font(78, bold=True)
    subtitle_font = font(38, bold=False)
    next_y = centered_multiline(draw, title, 108, title_font, (255, 255, 255, 255), 1120, 10)
    centered_multiline(draw, subtitle, next_y + 34, subtitle_font, (244, 244, 239, 235), 1060, 8)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(out_path, "PNG", optimize=True)


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
