#!/usr/bin/env python3
"""Apply the approved Tactile Territories / Pebble visual language to production UI."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCENE = ROOT / "Nine" / "GameScene.swift"
APP = ROOT / "Nine" / "NineApp.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Missing patch anchor: {label}")
    return text.replace(old, new, 1)


def patch_scene() -> None:
    s = SCENE.read_text()

    old = '''    private let canvasColor = SKColor.nine(hex: 0xF5F2EA)
    private let inkColor = SKColor.nine(hex: 0x262624)
    private let warningColor = SKColor.nine(hex: 0xC95555)
    private let hintColor = SKColor.nine(hex: 0x2F766E)
    private let regionPalette: [SKColor] = [
        .nine(hex: 0xF58E7E),
        .nine(hex: 0xF3B46D),
        .nine(hex: 0xEBCF72),
        .nine(hex: 0x8DC7A5),
        .nine(hex: 0x78C6C8),
        .nine(hex: 0x7EA9E1),
        .nine(hex: 0xA58AD8),
        .nine(hex: 0xD98EBC)
    ]
'''
    new = '''    private let canvasColor = SKColor.nine(hex: 0x0E1617)
    private let inkColor = SKColor.nine(hex: 0xF5F1E8)
    private let pebbleColor = SKColor.nine(hex: 0x171A1B)
    private let boardPlateColor = SKColor.nine(hex: 0x152124)
    private let warningColor = SKColor.nine(hex: 0xFF796B)
    private let hintColor = SKColor.nine(hex: 0x7AD6C3)
    private let accentColor = SKColor.nine(hex: 0x54BDD0)
    private let regionPalette: [SKColor] = [
        .nine(hex: 0xC97062),
        .nine(hex: 0xD79A59),
        .nine(hex: 0xCEB453),
        .nine(hex: 0x68AA82),
        .nine(hex: 0x58A9AB),
        .nine(hex: 0x648FC4),
        .nine(hex: 0x826CB8),
        .nine(hex: 0xAE6C92)
    ]
'''
    s = replace_once(s, old, new, "theme colors")

    old = '''        removeAllChildren()
        backgroundColor = canvasColor

        addHeader()
'''
    new = '''        removeAllChildren()
        backgroundColor = canvasColor
        addBackdrop()

        addHeader()
'''
    s = replace_once(s, old, new, "render backdrop")

    anchor = '''    private func addHeader() {
'''
    backdrop = '''    private func addBackdrop() {
        let haze: [(CGPoint, CGFloat, SKColor)] = [
            (CGPoint(x: size.width * 0.10, y: size.height * 0.88), size.width * 0.78, SKColor.nine(hex: 0x18342F)),
            (CGPoint(x: size.width * 0.94, y: size.height * 0.66), size.width * 0.70, SKColor.nine(hex: 0x173044)),
            (CGPoint(x: size.width * 0.50, y: size.height * 0.18), size.width * 0.85, SKColor.nine(hex: 0x2A241B))
        ]

        for (position, diameter, color) in haze {
            let glow = SKShapeNode(ellipseOf: CGSize(width: diameter, height: diameter))
            glow.position = position
            glow.fillColor = color.withAlphaComponent(0.23)
            glow.strokeColor = .clear
            glow.zPosition = -100
            addChild(glow)
        }
    }

'''
    s = replace_once(s, anchor, backdrop + anchor, "backdrop function")

    # Header typography and shorter production copy.
    s = s.replace('eyebrow.fontColor = inkColor.withAlphaComponent(0.48)', 'eyebrow.fontColor = inkColor.withAlphaComponent(0.46)')
    s = s.replace('title.fontSize = min(22, size.width * 0.055)', 'title.fontSize = min(21, size.width * 0.052)')
    s = s.replace('title.fontColor = inkColor', 'title.fontColor = inkColor')
    s = s.replace('subtitle.fontColor = inkColor.withAlphaComponent(0.56)', 'subtitle.fontColor = inkColor.withAlphaComponent(0.58)')
    s = s.replace('''                "Place one pebble in every territory",
                "One per row. One per column. No touching."
''', '''                "One pebble in every territory",
                "One per row  ·  One per column  ·  No touching"
''')

    # Dark tactile board plate.
    s = s.replace('shadow.fillColor = inkColor.withAlphaComponent(0.10)', 'shadow.fillColor = SKColor.black.withAlphaComponent(0.42)', 1)
    s = s.replace('plate.fillColor = SKColor.white.withAlphaComponent(0.58)', 'plate.fillColor = boardPlateColor.withAlphaComponent(0.98)', 1)
    s = s.replace('plate.strokeColor = SKColor.white.withAlphaComponent(0.72)', 'plate.strokeColor = SKColor.white.withAlphaComponent(0.10)', 1)
    s = s.replace('let visualCellSide = max(8, cellSide - 2.2)', 'let visualCellSide = max(8, cellSide - 4.0)', 1)

    old_cell = '''                let cell = SKShapeNode(
                    rectOf: CGSize(width: visualCellSide, height: visualCellSide),
                    cornerRadius: max(5, cellSide * 0.12)
                )
                cell.name = cellName(for: coordinate)
                cell.position = position
                cell.fillColor = regionPalette[regionID % regionPalette.count]
                    .withAlphaComponent(0.78)
                cell.strokeColor = SKColor.white.withAlphaComponent(0.42)
                cell.lineWidth = 1
                cell.zPosition = 0
                container.addChild(cell)
'''
    new_cell = '''                let cellShadow = SKShapeNode(
                    rectOf: CGSize(width: visualCellSide, height: visualCellSide),
                    cornerRadius: max(6, cellSide * 0.14)
                )
                cellShadow.position = CGPoint(x: position.x, y: position.y - 3)
                cellShadow.fillColor = SKColor.black.withAlphaComponent(0.30)
                cellShadow.strokeColor = .clear
                cellShadow.zPosition = -0.2
                container.addChild(cellShadow)

                let cell = SKShapeNode(
                    rectOf: CGSize(width: visualCellSide, height: visualCellSide),
                    cornerRadius: max(6, cellSide * 0.14)
                )
                cell.name = cellName(for: coordinate)
                cell.position = position
                cell.fillColor = regionPalette[regionID % regionPalette.count]
                    .withAlphaComponent(0.96)
                cell.strokeColor = SKColor.white.withAlphaComponent(0.13)
                cell.lineWidth = 1.2
                cell.zPosition = 0
                container.addChild(cell)

                let sheen = SKShapeNode(
                    rectOf: CGSize(width: visualCellSide * 0.78, height: 1.2),
                    cornerRadius: 0.6
                )
                sheen.position = CGPoint(
                    x: position.x,
                    y: position.y + visualCellSide * 0.34
                )
                sheen.fillColor = SKColor.white.withAlphaComponent(0.13)
                sheen.strokeColor = .clear
                sheen.zPosition = 0.5
                container.addChild(sheen)
'''
    s = replace_once(s, old_cell, new_cell, "tactile cells")

    s = s.replace('contactShadow.fillColor = inkColor.withAlphaComponent(0.18)', 'contactShadow.fillColor = SKColor.black.withAlphaComponent(0.48)', 1)
    s = s.replace('body.fillColor = inkColor', 'body.fillColor = pebbleColor', 1)
    s = s.replace('SKColor.white.withAlphaComponent(0.16)', 'SKColor.white.withAlphaComponent(0.22)', 1)
    s = s.replace('highlight.fillColor = SKColor.white.withAlphaComponent(0.42)', 'highlight.fillColor = SKColor.white.withAlphaComponent(0.55)', 1)

    # Production footer: settings owns sound/haptics, gameplay keeps three clear actions.
    start = s.index('    private func addFooter() {')
    end = s.index('    private func makeButton(', start)
    new_footer = '''    private func addFooter() {
        guard !isLevelComplete else { return }

        let footerY = max(72, size.height * 0.115)

        if !tutorialSession.isActive || playMode == .daily {
            let dailyTitle = playMode == .daily
                ? "Back to levels"
                : "Daily  ·  \\(progress.streak.currentCount)"
            let daily = makeButton(
                title: dailyTitle,
                name: NodeName.daily,
                width: 150
            )
            daily.position = CGPoint(x: size.width / 2, y: footerY + 62)
            addChild(daily)
        }

        let controls: [(String, String, CGFloat)] = [
            (moveHistory.canUndo ? "↶  Undo" : "↶  Undo —", NodeName.undo, 0.24),
            (activeHint == nil ? "◇  Hint" : "◇  Hint ✓", NodeName.hint, 0.50),
            ("↻  Reset", NodeName.reset, 0.76)
        ]

        for control in controls {
            let button = makeButton(
                title: control.0,
                name: control.1,
                width: 100
            )
            button.position = CGPoint(x: size.width * control.2, y: footerY)
            if control.1 == NodeName.undo && !moveHistory.canUndo {
                button.alpha = 0.34
            }
            addChild(button)
        }
    }

'''
    s = s[:start] + new_footer + s[end:]

    # Buttons become dark glass with luminous labels.
    s = s.replace('shape.fillColor = inkColor.withAlphaComponent(0.07)', 'shape.fillColor = SKColor.white.withAlphaComponent(0.075)', 1)
    s = s.replace('shape.strokeColor = inkColor.withAlphaComponent(0.10)', 'shape.strokeColor = SKColor.white.withAlphaComponent(0.12)', 1)
    s = s.replace('label.fontColor = inkColor.withAlphaComponent(0.78)', 'label.fontColor = inkColor.withAlphaComponent(0.88)', 1)

    # Completion surface is now a proper launch moment.
    s = s.replace('badge.fillColor = canvasColor.withAlphaComponent(0.97)', 'badge.fillColor = SKColor.nine(hex: 0x17332E).withAlphaComponent(0.98)', 1)
    s = s.replace('badge.strokeColor = SKColor.white.withAlphaComponent(0.8)', 'badge.strokeColor = accentColor.withAlphaComponent(0.55)', 1)
    old_solved = '''        if playMode == .daily {
            solved.text = "Daily complete · Streak \\(progress.streak.currentCount)"
        } else {
            solved.text = levelIndex == levels.count - 1
                ? "Pack complete"
                : "Beautiful."
        }
'''
    new_solved = '''        if playMode == .daily {
            solved.text = "Daily solved · \\(progress.streak.currentCount)-day streak"
        } else {
            solved.text = levelIndex == levels.count - 1
                ? "Pack complete!"
                : "Puzzle solved!"
        }
'''
    s = replace_once(s, old_solved, new_solved, "completion copy")

    old_next = '''        let next = makeButton(title: nextTitle, name: NodeName.next)
        next.position = CGPoint(x: 0, y: -30)
        next.setScale(0.88)
        badge.addChild(next)
'''
    new_next = '''        let next = makeButton(title: nextTitle, name: NodeName.next, width: 142)
        next.position = CGPoint(x: 0, y: -30)
        next.setScale(0.88)
        if let shape = next.children.compactMap({ $0 as? SKShapeNode }).first {
            shape.fillColor = accentColor.withAlphaComponent(0.92)
            shape.strokeColor = SKColor.white.withAlphaComponent(0.18)
        }
        if let label = next.children.compactMap({ $0 as? SKLabelNode }).first {
            label.fontColor = SKColor.nine(hex: 0x0C1A1D)
        }
        badge.addChild(next)
'''
    s = replace_once(s, old_next, new_next, "completion CTA")

    SCENE.write_text(s)


def patch_app() -> None:
    s = APP.read_text()
    old = '''            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Settings")
            .padding(.top, 14)
            .padding(.trailing, 14)
'''
    new = '''            if NineCapturePreset.current == nil {
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.28), in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Settings")
                .padding(.top, 14)
                .padding(.trailing, 14)
            }
'''
    s = replace_once(s, old, new, "settings button")
    if '.preferredColorScheme(.dark)' not in s:
        s = s.replace('''        .sheet(isPresented: $showsSettings) {
''', '''        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) {
''', 1)
    APP.write_text(s)


if __name__ == "__main__":
    patch_scene()
    patch_app()
    print("Applied production Tactile Territories theme")
