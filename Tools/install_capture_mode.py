#!/usr/bin/env python3
"""One-time patcher for deterministic App Store screenshot capture mode."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCENE = ROOT / "Nine" / "GameScene.swift"
TESTS = ROOT / "NineTests" / "NineFeedbackTests.swift"


def patch_scene() -> None:
    s = SCENE.read_text()

    if "enum NineCapturePreset: String" not in s:
        enum_code = '''enum NineCapturePreset: String, CaseIterable, Sendable {
    case simple
    case placement
    case territories
    case daily
    case solved

    static func parse(arguments: [String]) -> NineCapturePreset? {
        guard let flag = arguments.firstIndex(of: "--nine-capture"),
              arguments.indices.contains(flag + 1) else {
            return nil
        }
        return NineCapturePreset(rawValue: arguments[flag + 1])
    }

    static var current: NineCapturePreset? {
        parse(arguments: ProcessInfo.processInfo.arguments)
    }
}

'''
        s = s.replace("@MainActor\nfinal class GameScene: SKScene {", enum_code + "@MainActor\nfinal class GameScene: SKScene {", 1)

    state_anchor = "    private var isLevelComplete = false\n    private var hasPresentedScene = false\n"
    if "private let capturePreset" not in s:
        s = s.replace(state_anchor, state_anchor + "    private let capturePreset = NineCapturePreset.current\n", 1)

    old_did_move = '''    override func didMove(to view: SKView) {
        backgroundColor = canvasColor
        view.ignoresSiblingOrder = true
        beginAnalyticsSessionIfNeeded()
        beginGameCenterIfNeeded()

        if boardState == nil {
            restoreSavedSession()
        } else {
            renderScene()
        }
        hasPresentedScene = true
    }
'''
    new_did_move = '''    override func didMove(to view: SKView) {
        backgroundColor = canvasColor
        view.ignoresSiblingOrder = true

        if let capturePreset {
            applyCapturePreset(capturePreset)
        } else {
            beginAnalyticsSessionIfNeeded()
            beginGameCenterIfNeeded()
            if boardState == nil {
                restoreSavedSession()
            } else {
                renderScene()
            }
        }
        hasPresentedScene = true
    }
'''
    if old_did_move in s:
        s = s.replace(old_did_move, new_did_move, 1)

    if "private func applyCapturePreset" not in s:
        capture_function = '''    private func applyCapturePreset(_ preset: NineCapturePreset) {
        guard !levels.isEmpty else { return }

        // Capture mode is deterministic, offline, and side-effect free: no analytics,
        // persistence, ads, Game Center auth, or debug chrome.
        tutorialSession = NineTutorialSession(isActive: false)
        playMode = preset == .daily ? .daily : .progression
        dailyChallengeDayKey = preset == .daily ? "2026-09-19" : nil
        if preset == .daily {
            progress.streak = NineStreakState(
                currentCount: 5,
                longestCount: 8,
                lastCompletedDayKey: "2026-09-18"
            )
        }

        let standard = Array(levels.indices.dropFirst(tutorialLevelCount))
        func firstIndex(size: Int, offset: Int = 0) -> Int? {
            Array(standard.filter { levels[$0].definition.size == size }.dropFirst(offset)).first
        }

        let index: Int
        switch preset {
        case .simple:
            index = firstIndex(size: 6) ?? min(tutorialLevelCount, levels.count - 1)
        case .placement:
            index = firstIndex(size: 6, offset: 3) ?? firstIndex(size: 6) ?? 0
        case .territories:
            index = firstIndex(size: 9) ?? standard.last ?? 0
        case .daily:
            index = firstIndex(size: 7) ?? standard.first ?? 0
        case .solved:
            index = firstIndex(size: 8) ?? standard.last ?? 0
        }

        levelIndex = index
        let level = currentLevel
        let orderedSolution = level.solution.sorted()
        let markers: Set<BoardCoordinate>
        switch preset {
        case .simple:
            markers = Set(orderedSolution.dropLast(min(2, orderedSolution.count)))
        case .placement:
            markers = Set(orderedSolution.enumerated().compactMap { pair in
                pair.offset.isMultiple(of: 2) ? pair.element : nil
            })
        case .territories:
            markers = Set(orderedSolution.prefix(max(3, orderedSolution.count / 3)))
        case .daily:
            markers = Set(orderedSolution.prefix(max(3, orderedSolution.count / 2)))
        case .solved:
            markers = Set(orderedSolution)
        }

        let state = NineBoardState(level: level.definition, markers: markers)
        boardState = state
        moveHistory.reset(to: state.markers)
        activeHint = nil
        latestEvaluation = NineConstraintEngine.evaluate(state, level: level.definition)
        isLevelComplete = preset == .solved
        levelStartedAt = uptime
        replayRecorder = nil
        hasActiveAnalyticsLevel = false
        renderScene()

        if preset == .solved {
            presentCompletion()
        }
    }

'''
        s = s.replace("    private func restoreSavedSession() {", capture_function + "    private func restoreSavedSession() {", 1)

    kit_block = '''        let kit = SKLabelNode(fontNamed: "AvenirNext-Medium")
        kit.text = "GameTimeKit \\(GameTimeKit.version)"
        kit.fontSize = 10
        kit.fontColor = inkColor.withAlphaComponent(0.28)
        kit.horizontalAlignmentMode = .center
        kit.position = CGPoint(x: size.width / 2, y: 26)
        addChild(kit)
'''
    capture_safe_kit = '''        if capturePreset == nil {
            let kit = SKLabelNode(fontNamed: "AvenirNext-Medium")
            kit.text = "GameTimeKit \\(GameTimeKit.version)"
            kit.fontSize = 10
            kit.fontColor = inkColor.withAlphaComponent(0.28)
            kit.horizontalAlignmentMode = .center
            kit.position = CGPoint(x: size.width / 2, y: 26)
            addChild(kit)
        }
'''
    if kit_block in s:
        s = s.replace(kit_block, capture_safe_kit, 1)

    SCENE.write_text(s)


def patch_tests() -> None:
    s = TESTS.read_text()
    if "capturePresetParserIsDeterministic" not in s:
        s += '''

@Test func capturePresetParserIsDeterministic() {
    #expect(NineCapturePreset.parse(arguments: ["Nine"]) == nil)
    #expect(NineCapturePreset.parse(arguments: ["Nine", "--nine-capture", "simple"]) == .simple)
    #expect(NineCapturePreset.parse(arguments: ["Nine", "--nine-capture", "daily"]) == .daily)
    #expect(NineCapturePreset.parse(arguments: ["Nine", "--nine-capture", "unknown"]) == nil)
}
'''
        TESTS.write_text(s)


if __name__ == "__main__":
    patch_scene()
    patch_tests()
    print("Installed deterministic Nine capture mode")
