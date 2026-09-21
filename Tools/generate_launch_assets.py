#!/usr/bin/env python3
"""Generate Exactly One v1 artwork from the approved Tactile Territories / Pebble direction.

This is intentionally reproducible studio tooling: the shipping app icon and Game
Center achievement art are generated in-repo instead of depending on an external
PSD/illustrator handoff.
"""

from __future__ import annotations

import json
import math
import random
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
BG = (22, 25, 24)

ASSETS = ROOT / "Nine" / "Assets.xcassets"
APP_ICON = ASSETS / "AppIcon.appiconset"
ACHIEVEMENTS = ASSETS / "Achievements"
MARKETING_ICON = ROOT / "Marketing" / "AppStore" / "Icon"
MARKETING_GC = ROOT / "Marketing" / "AppStore" / "GameCenter"
MARKETING_SCREENSHOTS = ROOT / "Marketing" / "AppStore" / "Screenshots"
MARKETING_PREVIEW = ROOT / "Marketing" / "AppStore" / "Preview"
MARKETING_CAPTURE = ROOT / "Marketing" / "Capture"


def mkdirs() -> None:
    for path in [APP_ICON, ACHIEVEMENTS, MARKETING_ICON, MARKETING_GC,
                 MARKETING_SCREENSHOTS, MARKETING_PREVIEW, MARKETING_CAPTURE]:
        path.mkdir(parents=True, exist_ok=True)


def textured(base: tuple[int, int, int], sigma: float = 9.0) -> Image.Image:
    seed = sum((index + 1) * component for index, component in enumerate(base)) + int(sigma * 100)
    noise = Image.frombytes(
        "L",
        (SIZE, SIZE),
        random.Random(seed).randbytes(SIZE * SIZE),
    )
    noise = ImageOps.autocontrast(noise)
    tint = ImageOps.colorize(noise, tuple(max(0, c - 16) for c in base),
                             tuple(min(255, c + 18) for c in base))
    return Image.blend(Image.new("RGB", (SIZE, SIZE), base), tint, 0.22)


def paste_region(canvas: Image.Image, points: list[tuple[int, int]], color: tuple[int, int, int]) -> None:
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(5))

    shadow_mask = ImageChops.offset(mask, 0, 15).filter(ImageFilter.GaussianBlur(18))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.putalpha(shadow_mask.point(lambda p: int(p * 0.42)))
    canvas.alpha_composite(shadow)

    layer = textured(color, 8).convert("RGBA")
    layer.putalpha(mask)
    canvas.alpha_composite(layer)

    edge = mask.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(1.0))
    highlight = Image.new("RGBA", (SIZE, SIZE), (255, 255, 245, 0))
    highlight.putalpha(edge.point(lambda p: min(68, int(p * 0.28))))
    canvas.alpha_composite(highlight)


def sphere(size: int, light=(245, 243, 235), dark=(52, 55, 56)) -> Image.Image:
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    r = size * 0.48
    light_x, light_y = size * 0.36, size * 0.30
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - size / 2, y - size / 2)
            if d > r:
                continue
            shine = max(0.0, 1.0 - math.hypot(x - light_x, y - light_y) / r)
            depth = min(1.0, d / r)
            mix = min(1.0, max(0.0, 0.20 + depth * 0.72 - shine * 0.38))
            rgb = tuple(int(light[i] * (1 - mix) + dark[i] * mix) for i in range(3))
            px[x, y] = (*rgb, 255)
    return im.filter(ImageFilter.GaussianBlur(0.7))


def generate_app_icon() -> Image.Image:
    base = textured(BG, 5).convert("RGBA")
    regions = [
        ([(0, 0), (470, 0), (520, 85), (440, 210), (255, 365), (0, 350)], (78, 166, 188)),
        ([(470, 0), (1024, 0), (1024, 345), (860, 330), (730, 210), (520, 85)], (226, 181, 82)),
        ([(440, 210), (730, 210), (860, 330), (1024, 345), (1024, 650), (820, 615), (690, 505), (485, 500)], (132, 181, 88)),
        ([(690, 505), (820, 615), (1024, 650), (1024, 1024), (445, 1024), (435, 830), (550, 690)], (49, 137, 174)),
        ([(0, 350), (255, 365), (360, 515), (435, 830), (445, 1024), (0, 1024)], (213, 119, 80)),
        ([(255, 365), (440, 210), (485, 500), (550, 690), (435, 830), (360, 515)], (185, 159, 90)),
    ]
    for points, color in regions:
        paste_region(base, points, color)

    draw = ImageDraw.Draw(base, "RGBA")
    draw.ellipse((278, 250, 790, 762), fill=(9, 11, 11, 224))
    draw.ellipse((300, 272, 768, 740), outline=(235, 220, 175, 95), width=10)

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((345, 390, 735, 770), fill=(0, 0, 0, 155))
    base.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)))
    base.alpha_composite(sphere(390), (317, 292))
    return base.convert("RGB")


def medal_base(inner: tuple[int, int, int], rim: tuple[int, int, int]) -> Image.Image:
    base = textured(BG, 5).convert("RGBA")
    draw = ImageDraw.Draw(base, "RGBA")
    draw.ellipse((96, 108, 928, 940), fill=(0, 0, 0, 150))
    draw.ellipse((105, 96, 919, 910), fill=(*rim, 255))
    draw.ellipse((145, 136, 879, 870), fill=(*inner, 255))
    draw.ellipse((165, 156, 859, 850), outline=(255, 255, 255, 45), width=8)
    return base


def star_points(cx: float, cy: float, outer: float, inner: float) -> list[tuple[float, float]]:
    pts = []
    for i in range(10):
        angle = -math.pi / 2 + i * math.pi / 5
        radius = outer if i % 2 == 0 else inner
        pts.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return pts


def generate_first_solve() -> Image.Image:
    im = medal_base((58, 55, 48), (211, 160, 72))
    draw = ImageDraw.Draw(im, "RGBA")
    pts = star_points(512, 505, 255, 118)
    draw.polygon(pts, fill=(255, 194, 67, 255))
    draw.line(pts + [pts[0]], fill=(255, 235, 154, 220), width=10, joint="curve")
    return im.convert("RGB")


def generate_tutorial() -> Image.Image:
    im = medal_base((40, 67, 86), (179, 181, 177))
    draw = ImageDraw.Draw(im, "RGBA")
    draw.polygon([(250, 420), (512, 290), (775, 420), (512, 550)], fill=(225, 216, 195, 255))
    draw.polygon([(350, 480), (675, 480), (650, 650), (512, 720), (375, 650)], fill=(193, 184, 166, 255))
    draw.line((734, 428, 734, 655), fill=(232, 217, 181, 255), width=18)
    draw.ellipse((710, 640, 758, 688), fill=(232, 217, 181, 255))
    draw.ellipse((490, 400, 534, 444), fill=(90, 91, 89, 255))
    return im.convert("RGB")


def generate_first_daily() -> Image.Image:
    im = medal_base((50, 105, 70), (221, 177, 98))
    draw = ImageDraw.Draw(im, "RGBA")
    draw.rounded_rectangle((280, 310, 744, 724), radius=42, fill=(224, 181, 100, 255))
    draw.rectangle((280, 390, 744, 470), fill=(184, 134, 65, 255))
    draw.rounded_rectangle((350, 245, 410, 390), radius=22, fill=(238, 205, 135, 255))
    draw.rounded_rectangle((615, 245, 675, 390), radius=22, fill=(238, 205, 135, 255))
    for row in range(2):
        for col in range(4):
            x, y = 340 + col * 95, 510 + row * 92
            draw.rounded_rectangle((x, y, x + 52, y + 52), radius=9, fill=(71, 80, 65, 235))
    im.alpha_composite(sphere(165), (570, 535))
    return im.convert("RGB")


def generate_streak() -> Image.Image:
    im = medal_base((99, 48, 32), (203, 118, 62))
    draw = ImageDraw.Draw(im, "RGBA")
    outer = [(516, 218), (645, 390), (610, 480), (710, 590), (654, 730), (520, 804), (386, 744), (320, 625), (358, 510), (438, 420)]
    inner = [(520, 390), (588, 500), (548, 575), (608, 655), (530, 718), (442, 654), (455, 575), (410, 520)]
    draw.polygon(outer, fill=(244, 111, 42, 255))
    draw.polygon(inner, fill=(255, 191, 66, 255))
    return im.convert("RGB")


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    output = BytesIO()
    image.copy().save(output, "PNG", optimize=True)
    path.write_bytes(output.getvalue())


def write_catalog(icon: Image.Image, badges: dict[str, Image.Image]) -> None:
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    icon_name = "Nine-AppIcon-1024.png"
    save_png(icon, APP_ICON / icon_name)
    (APP_ICON / "Contents.json").write_text(json.dumps({
        "images": [{"filename": icon_name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}
    }, indent=2) + "\n")

    (ACHIEVEMENTS / "Contents.json").write_text(json.dumps({
        "info": {"author": "xcode", "version": 1},
        "properties": {"provides-namespace": True}
    }, indent=2) + "\n")
    for name, image in badges.items():
        folder = ACHIEVEMENTS / f"{name}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        filename = f"{name}-1024.png"
        save_png(image, folder / filename)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": filename, "idiom": "universal", "scale": "1x"}],
            "info": {"author": "xcode", "version": 1}
        }, indent=2) + "\n")


def write_marketing(icon: Image.Image, badges: dict[str, Image.Image]) -> None:
    save_png(icon, MARKETING_ICON / "Nine-AppIcon-1024.png")
    filenames = {
        "FirstSolve": "first-solve-1024.png",
        "TutorialComplete": "tutorial-complete-1024.png",
        "FirstDaily": "first-daily-1024.png",
        "Streak7": "streak-7-1024.png",
    }
    for name, image in badges.items():
        save_png(image, MARKETING_GC / filenames[name])

    (MARKETING_SCREENSHOTS / "README.md").write_text(
        "# App Store screenshot capture\n\n"
        "Final masters must come from the real production build. Planned story:\n\n"
        "1. A Surprisingly Simple Idea — one Pebble per row, column and territory.\n"
        "2. Place the Pebbles — tactile interaction and instant feedback.\n"
        "3. Master Irregular Territories — denser 8x8/9x9 board.\n"
        "4. Daily Puzzles — daily challenge and streak.\n"
        "5. That Satisfying Solved Moment — completion state / best time.\n\n"
        "Capture clean 6.9-inch portrait masters before adding copy.\n"
    )
    (MARKETING_PREVIEW / "README.md").write_text(
        "# App Preview\n\nOptional for v1. Do not block submission. If produced, use real gameplay footage only.\n"
    )
    (MARKETING_CAPTURE / "README.md").write_text(
        "# Capture masters\n\nPreserve clean real-build captures for App Store, Shorts, Reels and future Remotion automation.\n"
    )


def patch_xcode_project() -> None:
    path = ROOT / "Nine.xcodeproj" / "project.pbxproj"
    s = path.read_text()
    build_id = "A44000000000000000000001"
    file_id = "A44000000000000000000002"

    if f"{build_id} /* Assets.xcassets in Resources */" not in s:
        s = s.replace(
            "/* Begin PBXBuildFile section */\n",
            f"/* Begin PBXBuildFile section */\n\t\t{build_id} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* Assets.xcassets */; }};\n",
            1,
        )
    if f"{file_id} /* Assets.xcassets */ =" not in s:
        s = s.replace(
            "/* Begin PBXFileReference section */\n",
            f"/* Begin PBXFileReference section */\n\t\t{file_id} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};\n",
            1,
        )

    group_anchor = "\t\t\tchildren = (\n\t\t\t\tD20000000000000000000001 /* NineApp.swift */,\n"
    if f"{file_id} /* Assets.xcassets */," not in s:
        s = s.replace(group_anchor, group_anchor + f"\t\t\t\t{file_id} /* Assets.xcassets */,\n", 1)

    resource_anchor = "\t\t\tfiles = (\n\t\t\t\tD1000000000000000000000C /* NineLevels-v1.json in Resources */,\n"
    if f"{build_id} /* Assets.xcassets in Resources */," not in s:
        s = s.replace(resource_anchor, resource_anchor + f"\t\t\t\t{build_id} /* Assets.xcassets in Resources */,\n", 1)

    for marker in [
        "\t\tD13000000000000000000003 /* Debug */ = {",
        "\t\tD13000000000000000000004 /* Release */ = {",
    ]:
        start = s.index(marker)
        end = s.index("\t\t};", start)
        block = s[start:end]
        if "ASSETCATALOG_COMPILER_APPICON_NAME" not in block:
            settings = "\t\t\tbuildSettings = {"
            block = block.replace(settings, settings + "\n\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", 1)
            s = s[:start] + block + s[end:]
    path.write_text(s)


def patch_game_center_code() -> None:
    path = ROOT / "Nine" / "Experience" / "NineGameCenter.swift"
    s = path.read_text()
    if "var artworkAssetName: String" not in s:
        s += """

extension NineGameCenterAchievement {
    var artworkAssetName: String {
        switch self {
        case .firstSolve: return "Achievements/FirstSolve"
        case .tutorialComplete: return "Achievements/TutorialComplete"
        case .firstDaily: return "Achievements/FirstDaily"
        case .streakSeven: return "Achievements/Streak7"
        }
    }
}
"""
        path.write_text(s)
    else:
        s = s.replace('"Achievements.', '"Achievements/')
        path.write_text(s)


def patch_tests() -> None:
    path = ROOT / "NineTests" / "NineFeedbackTests.swift"
    s = path.read_text()
    if "bundledAchievementArtworkExists" not in s:
        if "import UIKit" not in s:
            s = s.replace("import Foundation\n", "import Foundation\nimport UIKit\n", 1)
        s += """

@MainActor
@Test func bundledAchievementArtworkExists() {
    for achievement in NineGameCenterAchievement.allCases {
        #expect(UIImage(named: achievement.artworkAssetName) != nil)
    }
}
"""
        path.write_text(s)


def write_manifest() -> None:
    path = ROOT / "Marketing" / "AppStore" / "ASSET_MANIFEST.md"
    path.write_text(
        "# Exactly One v1 launch asset manifest\n\n"
        "Approved direction: **Tactile Territories / Pebble**. Generated reproducibly by `Tools/generate_launch_assets.py`.\n\n"
        "| Asset | Dimensions | Shipping use | Status |\n"
        "|---|---:|---|---|\n"
        "| App icon | 1024x1024 | Xcode/App Store | Integrated |\n"
        "| First Solve | 1024x1024 | Game Center achievement | Ready |\n"
        "| Tutorial Complete | 1024x1024 | Game Center achievement | Ready |\n"
        "| First Daily | 1024x1024 | Game Center achievement | Ready |\n"
        "| 7-Day Streak | 1024x1024 | Game Center achievement | Ready |\n"
        "| iPhone screenshots x5 | current 6.9-inch portrait master | App Store | Capture from real build next |\n"
        "| App Preview | 15-30 seconds if used | App Store | Optional / non-blocking |\n\n"
        "Generated mockups are direction references only; submission screenshots must be real gameplay.\n"
    )


def main() -> None:
    mkdirs()
    icon = generate_app_icon()
    badges = {
        "FirstSolve": generate_first_solve(),
        "TutorialComplete": generate_tutorial(),
        "FirstDaily": generate_first_daily(),
        "Streak7": generate_streak(),
    }
    write_catalog(icon, badges)
    write_marketing(icon, badges)
    patch_xcode_project()
    patch_game_center_code()
    patch_tests()
    write_manifest()
    print("Generated and integrated Exactly One launch artwork")


if __name__ == "__main__":
    main()
