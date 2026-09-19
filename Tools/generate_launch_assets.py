#!/usr/bin/env python3
"""Generate Nine v1 launch artwork from the approved Tactile Territories direction.

The generator intentionally owns shipping icon/achievement artwork in-repo so the
first release never depends on an external design file. It emits the app asset
catalog plus App Store Connect copies and patches the Xcode project to compile
Assets.xcassets.
"""

from __future__ import annotations

import json
import math
import random
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
BG = (22, 25, 24)
INK = (38, 38, 36)
CANVAS = (245, 242, 234)
PALETTE = {
    "coral": (245, 142, 126),
    "apricot": (243, 180, 109),
    "butter": (235, 207, 114),
    "sage": (141, 199, 165),
    "aqua": (120, 198, 200),
    "sky": (126, 169, 225),
    "lavender": (165, 138, 216),
    "rose": (217, 142, 188),
}

ASSETS = ROOT / "Nine" / "Assets.xcassets"
APP_ICON = ASSETS / "AppIcon.appiconset"
ACHIEVEMENTS = ASSETS / "Achievements"
MARKETING_ICON = ROOT / "Marketing" / "AppStore" / "Icon"
MARKETING_GC = ROOT / "Marketing" / "AppStore" / "GameCenter"
MARKETING_SCREENSHOTS = ROOT / "Marketing" / "AppStore" / "Screenshots"
MARKETING_PREVIEW = ROOT / "Marketing" / "AppStore" / "Preview"
MARKETING_CAPTURE = ROOT / "Marketing" / "Capture"


def mkdirs() -> None:
    for path in [
        APP_ICON,
        ACHIEVEMENTS,
        MARKETING_ICON,
        MARKETING_GC,
        MARKETING_SCREENSHOTS,
        MARKETING_PREVIEW,
        MARKETING_CAPTURE,
    ]:
        path.mkdir(parents=True, exist_ok=True)


def noisy_surface(base: tuple[int, int, int], seed: int, strength: int = 12) -> Image.Image:
    random.seed(seed)
    img = Image.new("RGB", (SIZE, SIZE), base)
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            radial = math.hypot(x - SIZE * 0.38, y - SIZE * 0.28) / SIZE
            light = int(max(-8, 13 - radial * 24))
            noise = random.randint(-strength, strength)
            px[x, y] = tuple(max(0, min(255, c + light + noise)) for c in base)
    return img.filter(ImageFilter.GaussianBlur(0.45))


def rounded_mask(box: tuple[int, int, int, int], radius: int) -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def paste_region(canvas: Image.Image, points: list[tuple[int, int]], color: tuple[int, int, int], seed: int) -> None:
    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon(points, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(7))

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_mask = ImageChops.offset(mask, 0, 14).filter(ImageFilter.GaussianBlur(16))
    shadow.putalpha(shadow_mask.point(lambda p: int(p * 0.50)))
    canvas.alpha_composite(shadow)

    surface = noisy_surface(color, seed=seed, strength=8).convert("RGBA")
    surface.putalpha(mask)
    canvas.alpha_composite(surface)

    edge = mask.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(1.1))
    edge_layer = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    edge_layer.putalpha(edge.point(lambda p: min(80, int(p * 0.35))))
    canvas.alpha_composite(edge_layer)


def sphere(size: int, light: tuple[int, int, int], dark: tuple[int, int, int]) -> Image.Image:
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    cx, cy = size * 0.42, size * 0.36
    r = size * 0.48
    for y in range(size):
        for x in range(size):
            dx, dy = x - size / 2, y - size / 2
            d = math.hypot(dx, dy)
            if d > r:
                continue
            nx = (x - cx) / r
            ny = (y - cy) / r
            shine = max(0.0, 1.0 - math.hypot(nx, ny))
            depth = min(1.0, d / r)
            mix = min(1.0, max(0.0, depth * 0.78 - shine * 0.35 + 0.22))
            rgb = tuple(int(light[i] * (1 - mix) + dark[i] * mix) for i in range(3))
            px[x, y] = (*rgb, 255)
    return im.filter(ImageFilter.GaussianBlur(0.8))


def generate_app_icon() -> Image.Image:
    base = noisy_surface(BG, seed=9001, strength=4).convert("RGBA")

    # Full-bleed territories: intentionally no pre-rounded outer mask; iOS applies it.
    regions = [
        ([(0, 0), (470, 0), (520, 85), (440, 210), (255, 365), (0, 350)], (86, 173, 190), 1),
        ([(470, 0), (1024, 0), (1024, 345), (860, 330), (730, 210), (520, 85)], (224, 180, 83), 2),
        ([(440, 210), (730, 210), (860, 330), (1024, 345), (1024, 650), (820, 615), (690, 505), (485, 500)], (132, 181, 88), 3),
        ([(690, 505), (820, 615), (1024, 650), (1024, 1024), (445, 1024), (435, 830), (550, 690)], (50, 139, 176), 4),
        ([(0, 350), (255, 365), (360, 515), (435, 830), (445, 1024), (0, 1024)], (212, 119, 81), 5),
        ([(255, 365), (440, 210), (485, 500), (550, 690), (435, 830), (360, 515)], (186, 161, 92), 6),
    ]
    for pts, color, seed in regions:
        paste_region(base, pts, color, seed)

    # Central recessed well.
    draw = ImageDraw.Draw(base, "RGBA")
    draw.ellipse((278, 250, 790, 762), fill=(10, 12, 12, 215))
    draw.ellipse((300, 272, 768, 740), outline=(235, 220, 175, 100), width=10)

    pebble = sphere(390, (245, 243, 235), (55, 58, 59))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse((348, 394, 736, 760), fill=(0, 0, 0, 155))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    base.alpha_composite(shadow)
    base.alpha_composite(pebble, (317, 292))

    # Gentle highlight around the piece.
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((307, 282, 717, 692), outline=(255, 255, 240, 70), width=7)
    base.alpha_composite(glow.filter(ImageFilter.GaussianBlur(2)))
    return base.convert("RGB")


def medal_base(inner: tuple[int, int, int], rim: tuple[int, int, int], seed: int) -> Image.Image:
    base = noisy_surface(BG, seed=seed, strength=4).convert("RGBA")
    draw = ImageDraw.Draw(base, "RGBA")
    draw.ellipse((98, 98, 926, 926), fill=(0, 0, 0, 160))
    draw.ellipse((112, 105, 912, 905), fill=(*rim, 255))
    draw.ellipse((145, 138, 879, 872), fill=(*inner, 255))
    draw.ellipse((168, 160, 856, 848), outline=(255, 255, 255, 45), width=8)
    return base


def star_points(cx: float, cy: float, outer: float, inner: float, n: int = 5) -> list[tuple[float, float]]:
    pts = []
    for i in range(n * 2):
        a = -math.pi / 2 + i * math.pi / n
        r = outer if i % 2 == 0 else inner
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def generate_first_solve() -> Image.Image:
    im = medal_base((58, 55, 48), (211, 160, 72), 101)
    draw = ImageDraw.Draw(im, "RGBA")
    pts = star_points(512, 500, 255, 115)
    draw.polygon(pts, fill=(255, 193, 64, 255))
    draw.line(pts + [pts[0]], fill=(255, 235, 154, 220), width=10, joint="curve")
    return im.convert("RGB")


def generate_tutorial() -> Image.Image:
    im = medal_base((40, 67, 86), (179, 181, 177), 202)
    draw = ImageDraw.Draw(im, "RGBA")
    # Graduation cap.
    draw.polygon([(250, 420), (512, 290), (775, 420), (512, 550)], fill=(225, 216, 195, 255))
    draw.polygon([(350, 480), (675, 480), (650, 650), (512, 720), (375, 650)], fill=(193, 184, 166, 255))
    draw.line((734, 428, 734, 655), fill=(232, 217, 181, 255), width=18)
    draw.ellipse((710, 640, 758, 688), fill=(232, 217, 181, 255))
    draw.ellipse((490, 400, 534, 444), fill=(90, 91, 89, 255))
    return im.convert("RGB")


def generate_first_daily() -> Image.Image:
    im = medal_base((50, 105, 70), (221, 177, 98), 303)
    draw = ImageDraw.Draw(im, "RGBA")
    # Calendar.
    draw.rounded_rectangle((280, 310, 744, 724), radius=42, fill=(224, 181, 100, 255))
    draw.rectangle((280, 390, 744, 470), fill=(184, 134, 65, 255))
    draw.rounded_rectangle((350, 245, 410, 390), radius=22, fill=(238, 205, 135, 255))
    draw.rounded_rectangle((615, 245, 675, 390), radius=22, fill=(238, 205, 135, 255))
    for row in range(2):
        for col in range(4):
            x = 340 + col * 95
            y = 510 + row * 92
            draw.rounded_rectangle((x, y, x + 52, y + 52), radius=9, fill=(71, 80, 65, 235))
    pebble = sphere(165, (233, 230, 215), (70, 73, 71))
    im.alpha_composite(pebble, (570, 535))
    return im.convert("RGB")


def generate_streak() -> Image.Image:
    im = medal_base((99, 48, 32), (203, 118, 62), 404)
    draw = ImageDraw.Draw(im, "RGBA")
    outer = [(516, 218), (645, 390), (610, 480), (710, 590), (654, 730), (520, 804), (386, 744), (320, 625), (358, 510), (438, 420)]
    inner = [(520, 390), (588, 500), (548, 575), (608, 655), (530, 718), (442, 654), (455, 575), (410, 520)]
    draw.polygon(outer, fill=(244, 111, 42, 255))
    draw.polygon(inner, fill=(255, 191, 66, 255))
    return im.convert("RGB")


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def write_asset_catalog(icon: Image.Image, achievements: dict[str, Image.Image]) -> None:
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    icon_name = "Nine-AppIcon-1024.png"
    save_png(icon, APP_ICON / icon_name)
    (APP_ICON / "Contents.json").write_text(json.dumps({
        "images": [{"filename": icon_name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")

    (ACHIEVEMENTS / "Contents.json").write_text(json.dumps({
        "info": {"author": "xcode", "version": 1},
        "properties": {"provides-namespace": True},
    }, indent=2) + "\n")

    for asset_name, image in achievements.items():
        imageset = ACHIEVEMENTS / f"{asset_name}.imageset"
        imageset.mkdir(parents=True, exist_ok=True)
        filename = f"{asset_name}-1024.png"
        save_png(image, imageset / filename)
        (imageset / "Contents.json").write_text(json.dumps({
            "images": [{"filename": filename, "idiom": "universal", "scale": "1x"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n")


def write_marketing_copies(icon: Image.Image, achievements: dict[str, Image.Image]) -> None:
    save_png(icon, MARKETING_ICON / "Nine-AppIcon-1024.png")
    names = {
        "FirstSolve": "first-solve-1024.png",
        "TutorialComplete": "tutorial-complete-1024.png",
        "FirstDaily": "first-daily-1024.png",
        "Streak7": "streak-7-1024.png",
    }
    for key, image in achievements.items():
        save_png(image, MARKETING_GC / names[key])

    (MARKETING_SCREENSHOTS / "README.md").write_text(
        "# App Store screenshot capture\n\n"
        "Final screenshot masters must come from the real production build. Planned launch story:\n\n"
        "1. A Surprisingly Simple Idea — one Pebble per row, column and territory.\n"
        "2. Place the Pebbles — tactile interaction and instant feedback.\n"
        "3. Master Irregular Territories — denser 8x8/9x9 board.\n"
        "4. Daily Puzzles — daily challenge and streak.\n"
        "5. That Satisfying Solved Moment — completion state / best time.\n\n"
        "Capture clean 6.9-inch portrait masters before adding copy.\n"
    )
    (MARKETING_PREVIEW / "README.md").write_text(
        "# App Preview\n\nOptional for v1. Do not block submission. If produced, use only real gameplay footage.\n"
    )
    (MARKETING_CAPTURE / "README.md").write_text(
        "# Capture masters\n\nPreserve clean real-build captures for App Store, Shorts, Reels and future Remotion automation.\n"
    )


def patch_xcode_project() -> None:
    path = ROOT / "Nine.xcodeproj" / "project.pbxproj"
    s = path.read_text()
    if "A44000000000000000000001 /* Assets.xcassets in Resources */" not in s:
        s = s.replace(
            "/* Begin PBXBuildFile section */\n",
            "/* Begin PBXBuildFile section */\n\t\tA44000000000000000000001 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = A44000000000000000000002 /* Assets.xcassets */; };\n",
            1,
        )
    if "A44000000000000000000002 /* Assets.xcassets */ =" not in s:
        s = s.replace(
            "/* Begin PBXFileReference section */\n",
            "/* Begin PBXFileReference section */\n\t\tA44000000000000000000002 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };\n",
            1,
        )
    if "A44000000000000000000002 /* Assets.xcassets */," not in s:
        s = s.replace(
            "\t\t\tchildren = (\n\t\t\t\tD20000000000000000000001 /* NineApp.swift */,
",
            "\t\t\tchildren = (\n\t\t\t\tD20000000000000000000001 /* NineApp.swift */,\n\t\t\t\tA44000000000000000000002 /* Assets.xcassets */,\n",
            1,
        )
    if "A44000000000000000000001 /* Assets.xcassets in Resources */," not in s:
        s = s.replace(
            "\t\t\tfiles = (\n\t\t\t\tD1000000000000000000000C /* NineLevels-v1.json in Resources */,
",
            "\t\t\tfiles = (\n\t\t\t\tD1000000000000000000000C /* NineLevels-v1.json in Resources */,\n\t\t\t\tA44000000000000000000001 /* Assets.xcassets in Resources */,\n",
            1,
        )
    # App icon setting in both Nine target configurations only.
    for marker in [
        "\t\tD13000000000000000000003 /* Debug */ = {",
        "\t\tD13000000000000000000004 /* Release */ = {",
    ]:
        start = s.index(marker)
        end = s.index("\t\t};", start)
        block = s[start:end]
        if "ASSETCATALOG_COMPILER_APPICON_NAME" not in block:
            insert = block.index("\t\t\tbuildSettings = {") + len("\t\t\tbuildSettings = {")
            block = block[:insert] + "\n\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;" + block[insert:]
            s = s[:start] + block + s[end:]
    path.write_text(s)


def patch_game_center_code() -> None:
    path = ROOT / "Nine" / "Experience" / "NineGameCenter.swift"
    s = path.read_text()
    marker = "extension NineGameCenterAchievement {\n    var artworkAssetName: String"
    if marker not in s:
        s += """

extension NineGameCenterAchievement {
    var artworkAssetName: String {
        switch self {
        case .firstSolve:
            return "Achievements.FirstSolve"
        case .tutorialComplete:
            return "Achievements.TutorialComplete"
        case .firstDaily:
            return "Achievements.FirstDaily"
        case .streakSeven:
            return "Achievements.Streak7"
        }
    }
}
"""
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
    manifest = ROOT / "Marketing" / "AppStore" / "ASSET_MANIFEST.md"
    manifest.write_text(
        "# Nine v1 launch asset manifest\n\n"
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
        "Do not replace real gameplay screenshots with generated mockups.\n"
    )


def main() -> None:
    mkdirs()
    icon = generate_app_icon()
    achievement_images = {
        "FirstSolve": generate_first_solve(),
        "TutorialComplete": generate_tutorial(),
        "FirstDaily": generate_first_daily(),
        "Streak7": generate_streak(),
    }
    write_asset_catalog(icon, achievement_images)
    write_marketing_copies(icon, achievement_images)
    patch_xcode_project()
    patch_game_center_code()
    patch_tests()
    write_manifest()
    print("Generated Nine launch assets and integrated Assets.xcassets")


if __name__ == "__main__":
    main()
