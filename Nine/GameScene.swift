import Foundation
import SpriteKit
import UIKit
import GameTimeCore
import GameTimeExperience

@MainActor
final class GameScene: SKScene {
    private enum NodeName {
        static let reset = "action:reset"
        static let undo = "action:undo"
        static let hint = "action:hint"
        static let next = "action:next"
        static let sound = "action:sound"
        static let haptics = "action:haptics"
        static let daily = "action:daily"
        static let cellPrefix = "cell:"
    }

    private let canvasColor = SKColor.nine(hex: 0xF5F2EA)
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

    private let levels = PrototypeLevels.production
    private let tutorialStore = NineTutorialCompletionStore()
    private lazy var tutorialSession = NineTutorialSession(
        isActive: !tutorialStore.isComplete
    )
    private var emittedTutorialEvents: [NineTutorialEvent] = []

    private let feedbackPreferences = NineFeedbackPreferenceStore()
    private lazy var feedback = NineFeedbackEngine(preferences: feedbackPreferences)

    private let progressStore = NineProgressStore()
    private lazy var progress = progressStore.load(levels: levels)
    private var playMode: NinePlayMode = .progression
    private var dailyChallengeDayKey: String?
    private var levelStartedAt: TimeInterval = 0

    private var moveHistory = NineMoveHistory()
    private var activeHint: NineHint?
    private var emittedGameplayIntents: [NineGameplayIntent] = []

    private var levelIndex = 0
    private var boardState: NineBoardState?
    private var latestEvaluation = BoardEvaluation(violations: [], isSolved: false)
    private var isLevelComplete = false
    private var hasPresentedScene = false

    private var tutorialLevelCount: Int {
        min(5, levels.count)
    }

    private var currentLevel: PrototypeLevel {
        levels[levelIndex]
    }

    private var uptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private var todayDayKey: String {
        NineUTCDate.dayKey(for: Date())
    }

    private var activeDailyDayKey: String {
        dailyChallengeDayKey ?? todayDayKey
    }

    override func didMove(to view: SKView) {
        backgroundColor = canvasColor
        view.ignoresSiblingOrder = true

        if boardState == nil {
            restoreSavedSession()
        } else {
            renderScene()
        }
        hasPresentedScene = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard hasPresentedScene else { return }
        renderScene()
    }

    override func update(_ currentTime: TimeInterval) {
        guard playMode == .progression,
              tutorialSession.isActive,
              levelIndex < tutorialLevelCount,
              !isLevelComplete else {
            return
        }

        let events = tutorialSession.assistanceDue(
            levelID: currentLevel.definition.id,
            now: uptime
        )
        guard !events.isEmpty else { return }

        emitTutorialEvents(events)
        renderScene()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self) else { return }
        let hitNodes = nodes(at: location)

        if hitNodes.contains(where: { $0.name == NodeName.sound }) {
            toggleSound()
            return
        }

        if hitNodes.contains(where: { $0.name == NodeName.haptics }) {
            toggleHaptics()
            return
        }

        if hitNodes.contains(where: { $0.name == NodeName.daily }) {
            toggleDailyChallenge()
            return
        }

        if hitNodes.contains(where: { $0.name == NodeName.undo }) {
            undoCurrentMove()
            return
        }

        if hitNodes.contains(where: { $0.name == NodeName.hint }) {
            previewHint()
            return
        }

        if hitNodes.contains(where: { $0.name == NodeName.reset }) {
            resetCurrentLevel()
            return
        }

        if hitNodes.contains(where: { $0.name == NodeName.next }) {
            advanceLevel()
            return
        }

        guard !isLevelComplete,
              let coordinate = hitNodes.compactMap({ coordinate(from: $0.name) }).first,
              var state = boardState else {
            return
        }

        let markerWasPresent = state.markers.contains(coordinate)
        let changed = state.toggleMarker(
            at: coordinate,
            level: currentLevel.definition
        )
        guard changed else { return }

        boardState = state
        moveHistory.record(state.markers)
        activeHint = nil
        latestEvaluation = NineConstraintEngine.evaluate(
            state,
            level: currentLevel.definition
        )
        persistActiveSession(state)
        recordGameplayIntent(
            kind: markerWasPresent ? .remove : .place,
            coordinate: coordinate
        )

        let placedMarker = !markerWasPresent && state.markers.contains(coordinate)
        let invalidPlacement = placedMarker
            && latestEvaluation.conflictingCoordinates.contains(coordinate)

        if playMode == .progression,
           tutorialSession.isActive,
           levelIndex < tutorialLevelCount {
            emitTutorialEvents(
                tutorialSession.recordInteraction(
                    isValid: !invalidPlacement,
                    levelID: currentLevel.definition.id,
                    now: uptime
                )
            )
        }

        if playMode == .progression,
           latestEvaluation.isSolved,
           levelIndex == tutorialLevelCount - 1,
           tutorialSession.isActive {
            tutorialStore.markComplete()
            emitTutorialEvents(
                tutorialSession.complete(levelID: currentLevel.definition.id)
            )
        }

        renderScene()

        if markerWasPresent {
            feedback.play(.removal)
        } else if invalidPlacement {
            feedback.play(.invalid)
            animateConflict(at: coordinate)
        } else {
            feedback.play(.placement)
            animatePlacement(at: coordinate)
        }

        if latestEvaluation.isSolved {
            isLevelComplete = true
            recordCompletion()
            let isMilestone = playMode == .daily
                || (levelIndex + 1).isMultiple(of: 5)
            feedback.play(isMilestone ? .milestone : .solved)
            presentCompletion()
        }
    }

    private func restoreSavedSession() {
        guard !levels.isEmpty else {
            preconditionFailure("Nine requires at least one validated bundled level")
        }

        if let session = progress.activeSession,
           let index = levels.firstIndex(where: {
               $0.definition.id == session.levelID
           }) {
            playMode = session.mode
            dailyChallengeDayKey = session.mode == .daily
                ? (session.dayKey ?? todayDayKey)
                : nil
            loadLevel(
                at: index,
                restoring: Set(session.markers)
            )
            return
        }

        playMode = .progression
        dailyChallengeDayKey = nil
        let currentID = progress.currentLevelID
        let index = levels.firstIndex(where: {
            $0.definition.id == currentID
        }) ?? 0
        loadLevel(at: index)
    }

    private func loadLevel(
        at index: Int,
        restoring restoredMarkers: Set<BoardCoordinate>? = nil
    ) {
        guard !levels.isEmpty else {
            preconditionFailure("Nine requires at least one validated bundled level")
        }

        levelIndex = max(0, min(index, levels.count - 1))
        let level = currentLevel
        let markers = restoredMarkers ?? level.initialMarkers
        let state = NineBoardState(
            level: level.definition,
            markers: markers
        )
        boardState = state
        moveHistory.reset(to: state.markers)
        activeHint = nil
        latestEvaluation = NineConstraintEngine.evaluate(
            state,
            level: level.definition
        )
        isLevelComplete = false
        levelStartedAt = uptime

        if playMode == .progression {
            progress.currentLevelID = level.definition.id
        }
        persistActiveSession(state)

        if playMode == .progression,
           tutorialSession.isActive,
           levelIndex < tutorialLevelCount {
            emitTutorialEvents(
                tutorialSession.beginLevel(
                    index: levelIndex,
                    levelID: level.definition.id,
                    now: uptime
                )
            )
        }
        renderScene()
    }

    private func persistActiveSession(_ state: NineBoardState) {
        progress.activeSession = NineSavedSession(
            mode: playMode,
            levelID: currentLevel.definition.id,
            dayKey: playMode == .daily ? activeDailyDayKey : nil,
            markers: state.markers.sorted()
        )
        progressStore.save(progress)
    }

    private func undoCurrentMove() {
        guard !isLevelComplete,
              let previousMarkers = moveHistory.undo() else {
            return
        }

        let restored = NineBoardState(
            level: currentLevel.definition,
            markers: previousMarkers
        )
        boardState = restored
        activeHint = nil
        latestEvaluation = NineConstraintEngine.evaluate(
            restored,
            level: currentLevel.definition
        )
        persistActiveSession(restored)
        recordGameplayIntent(kind: .undo)
        feedback.play(.undo)
        renderScene()
    }

    private func previewHint() {
        guard !isLevelComplete,
              let state = boardState,
              let hint = NineHintEngine.nextHint(
                level: currentLevel,
                state: state
              ) else {
            return
        }

        activeHint = hint
        recordGameplayIntent(
            kind: .hintPreview,
            coordinate: hint.coordinate
        )
        feedback.play(.hint)
        renderScene()
    }

    private func resetCurrentLevel() {
        let level = currentLevel
        let resetState = NineBoardState(
            level: level.definition,
            markers: level.initialMarkers
        )
        boardState = resetState
        moveHistory.reset(to: resetState.markers)
        activeHint = nil
        latestEvaluation = NineConstraintEngine.evaluate(
            resetState,
            level: level.definition
        )
        isLevelComplete = false
        levelStartedAt = uptime
        persistActiveSession(resetState)
        recordGameplayIntent(kind: .reset)

        if playMode == .progression,
           tutorialSession.isActive,
           levelIndex < tutorialLevelCount {
            emitTutorialEvents(
                tutorialSession.recordInteraction(
                    isValid: true,
                    levelID: level.definition.id,
                    now: uptime
                )
            )
        }
        feedback.play(.reset)
        renderScene()
    }

    private func recordCompletion() {
        let elapsed = max(0, uptime - levelStartedAt)
        let levelID = currentLevel.definition.id

        switch playMode {
        case .progression:
            let nextLevelID = levels.indices.contains(levelIndex + 1)
                ? levels[levelIndex + 1].definition.id
                : nil
            progress.recordProgressionCompletion(
                levelID: levelID,
                nextLevelID: nextLevelID,
                durationSeconds: elapsed,
                dayKey: todayDayKey
            )
        case .daily:
            progress.recordDailyCompletion(
                levelID: levelID,
                durationSeconds: elapsed,
                dayKey: activeDailyDayKey
            )
        }

        progressStore.save(progress)
    }

    private func advanceLevel() {
        if playMode == .daily {
            resumeProgression()
            return
        }

        let nextIndex = levelIndex + 1
        if nextIndex < levels.count {
            loadLevel(at: nextIndex)
        } else {
            progress.currentLevelID = levels.first?.definition.id
            progressStore.save(progress)
            loadLevel(at: 0)
        }
    }

    private func toggleDailyChallenge() {
        guard !tutorialSession.isActive || playMode == .daily else { return }

        if playMode == .daily {
            resumeProgression()
            return
        }

        guard let dailyIndex = NineDailyChallenge.levelIndex(
            for: Date(),
            in: levels,
            excludingFirst: tutorialLevelCount
        ) else {
            return
        }

        playMode = .daily
        dailyChallengeDayKey = todayDayKey
        loadLevel(at: dailyIndex)
    }

    private func resumeProgression() {
        playMode = .progression
        dailyChallengeDayKey = nil
        let targetID = progress.currentLevelID
        let targetIndex = levels.firstIndex(where: {
            $0.definition.id == targetID
        }) ?? 0
        loadLevel(at: targetIndex)
    }

    private func toggleSound() {
        let nextValue = !feedbackPreferences.current.soundEnabled
        feedbackPreferences.setSoundEnabled(nextValue)
        if nextValue {
            feedback.play(.placement)
        }
        renderScene()
    }

    private func toggleHaptics() {
        let nextValue = !feedbackPreferences.current.hapticsEnabled
        feedbackPreferences.setHapticsEnabled(nextValue)
        if nextValue {
            feedback.play(.placement)
        }
        renderScene()
    }

    private func renderScene() {
        guard let state = boardState else { return }

        removeAllChildren()
        backgroundColor = canvasColor

        addHeader()

        let boardSide = min(size.width - 36, size.height * 0.54, 470)
        let boardCenter = CGPoint(
            x: size.width / 2,
            y: size.height * 0.53
        )
        let board = makeBoard(
            side: boardSide,
            state: state
        )
        board.position = boardCenter
        addChild(board)

        addFooter()
    }

    private func addHeader() {
        let eyebrow = SKLabelNode(fontNamed: "AvenirNext-Medium")
        if playMode == .daily {
            eyebrow.text = "DAILY  ·  \(activeDailyDayKey)"
        } else if tutorialSession.isActive && levelIndex < tutorialLevelCount {
            eyebrow.text = "LEARN BY PLAYING  ·  \(levelIndex + 1) / \(tutorialLevelCount)"
        } else {
            eyebrow.text = "PUZZLE  \(levelIndex + 1) / \(levels.count)"
        }
        eyebrow.fontSize = 12
        eyebrow.fontColor = inkColor.withAlphaComponent(0.48)
        eyebrow.horizontalAlignmentMode = .center
        eyebrow.position = CGPoint(x: size.width / 2, y: size.height - 78)
        addChild(eyebrow)

        let copy = headerCopy

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.text = copy.title
        title.fontSize = min(22, size.width * 0.055)
        title.fontColor = inkColor
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: size.width / 2, y: size.height - 112)
        addChild(title)

        let subtitle = SKLabelNode(fontNamed: "AvenirNext-Regular")
        subtitle.text = copy.subtitle
        subtitle.fontSize = 13
        subtitle.fontColor = inkColor.withAlphaComponent(0.56)
        subtitle.horizontalAlignmentMode = .center
        subtitle.position = CGPoint(x: size.width / 2, y: size.height - 140)
        addChild(subtitle)
    }

    private var headerCopy: (title: String, subtitle: String) {
        if let activeHint {
            let action = activeHint.action == .place ? "Place" : "Remove"
            return ("Hint: \(action.lowercased()) the marked pebble", activeHint.reason)
        }

        if playMode == .daily {
            let count = progress.streak.currentCount
            let streakCopy = count > 0
                ? "Current streak: \(count). One missed day is forgiven."
                : "Solve once today to start your streak."
            return ("Today’s puzzle", streakCopy)
        }

        guard tutorialSession.isActive && levelIndex < tutorialLevelCount else {
            return (
                "Place one pebble in every territory",
                "One per row. One per column. No touching."
            )
        }

        switch levelIndex {
        case 0:
            return ("Place the last pebble", "Finish this nearly-complete board.")
        case 1:
            return ("One per row. One per column.", "Keep every row and column unique.")
        case 2:
            return ("One in every territory", "Each colored territory gets one pebble.")
        case 3:
            return ("Pebbles can’t touch", "Leave at least one cell between neighbors.")
        default:
            return ("You’ve got it", "Use all four rules together.")
        }
    }

    private func makeBoard(
        side: CGFloat,
        state: NineBoardState
    ) -> SKNode {
        let container = SKNode()
        container.name = "board"

        let shadow = SKShapeNode(
            rectOf: CGSize(width: side + 10, height: side + 10),
            cornerRadius: 24
        )
        shadow.fillColor = inkColor.withAlphaComponent(0.10)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -7)
        shadow.zPosition = -3
        container.addChild(shadow)

        let plate = SKShapeNode(
            rectOf: CGSize(width: side + 10, height: side + 10),
            cornerRadius: 24
        )
        plate.fillColor = SKColor.white.withAlphaComponent(0.58)
        plate.strokeColor = SKColor.white.withAlphaComponent(0.72)
        plate.lineWidth = 1
        plate.zPosition = -2
        container.addChild(plate)

        let dimension = currentLevel.definition.size
        let cellSide = side / CGFloat(dimension)
        let visualCellSide = max(8, cellSide - 2.2)
        let half = CGFloat(dimension - 1) / 2
        let conflicts = latestEvaluation.conflictingCoordinates

        for row in 0..<dimension {
            for column in 0..<dimension {
                let coordinate = BoardCoordinate(row: row, column: column)
                let regionID = currentLevel.definition.regionID(at: coordinate) ?? 0
                let position = boardPosition(
                    for: coordinate,
                    cellSide: cellSide,
                    half: half
                )

                let cell = SKShapeNode(
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

                if state.markers.contains(coordinate) {
                    let pebble = makePebble(
                        diameter: cellSide * 0.54,
                        isConflicting: conflicts.contains(coordinate)
                    )
                    pebble.name = cellName(for: coordinate)
                    pebble.position = position
                    pebble.zPosition = 3
                    container.addChild(pebble)
                }
            }
        }

        addTutorialGuidance(
            to: container,
            side: side,
            cellSide: cellSide,
            half: half,
            state: state
        )
        addHintGuidance(
            to: container,
            side: side,
            cellSide: cellSide,
            half: half
        )

        return container
    }

    private func addTutorialGuidance(
        to board: SKNode,
        side: CGFloat,
        cellSide: CGFloat,
        half: CGFloat,
        state: NineBoardState
    ) {
        guard activeHint == nil,
              playMode == .progression,
              tutorialSession.isActive,
              levelIndex < tutorialLevelCount,
              tutorialSession.currentAssistance != .none,
              let target = currentLevel.solution.first(where: {
                  !state.markers.contains($0)
              }) else {
            return
        }

        let targetPosition = boardPosition(
            for: target,
            cellSide: cellSide,
            half: half
        )

        let ring = SKShapeNode(
            ellipseOf: CGSize(width: cellSide * 0.76, height: cellSide * 0.76)
        )
        ring.position = targetPosition
        ring.fillColor = .clear
        ring.strokeColor = SKColor.white.withAlphaComponent(0.96)
        ring.lineWidth = tutorialSession.currentAssistance == .strong ? 4 : 2.5
        ring.glowWidth = tutorialSession.currentAssistance == .strong ? 3 : 1
        ring.zPosition = 8
        board.addChild(ring)

        if UIAccessibility.isReduceMotionEnabled {
            ring.alpha = 0.82
        } else {
            ring.run(
                .repeatForever(
                    .sequence([
                        .group([
                            .scale(to: 1.16, duration: 0.55),
                            .fadeAlpha(to: 0.40, duration: 0.55)
                        ]),
                        .group([
                            .scale(to: 1.0, duration: 0.55),
                            .fadeAlpha(to: 1.0, duration: 0.55)
                        ])
                    ])
                )
            )
        }

        guard tutorialSession.currentAssistance >= .contextual else { return }

        let callout = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        callout.text = tutorialGuidanceText
        callout.fontSize = 13
        callout.fontColor = inkColor.withAlphaComponent(0.82)
        callout.horizontalAlignmentMode = .center
        callout.verticalAlignmentMode = .center
        callout.position = CGPoint(x: 0, y: -side / 2 - 28)
        callout.zPosition = 10
        board.addChild(callout)

        if tutorialSession.currentAssistance == .strong {
            let pointer = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            pointer.text = "↓"
            pointer.fontSize = 24
            pointer.fontColor = inkColor.withAlphaComponent(0.78)
            pointer.position = CGPoint(
                x: targetPosition.x,
                y: targetPosition.y + cellSide * 0.48
            )
            pointer.zPosition = 9
            board.addChild(pointer)
        }
    }

    private func addHintGuidance(
        to board: SKNode,
        side: CGFloat,
        cellSide: CGFloat,
        half: CGFloat
    ) {
        guard let activeHint else { return }

        let targetPosition = boardPosition(
            for: activeHint.coordinate,
            cellSide: cellSide,
            half: half
        )

        let ring = SKShapeNode(
            ellipseOf: CGSize(width: cellSide * 0.80, height: cellSide * 0.80)
        )
        ring.position = targetPosition
        ring.fillColor = .clear
        ring.strokeColor = hintColor
        ring.lineWidth = 3
        ring.glowWidth = 1
        ring.zPosition = 9
        board.addChild(ring)

        let symbol = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        symbol.text = activeHint.action == .place ? "+" : "−"
        symbol.fontSize = max(18, cellSide * 0.30)
        symbol.fontColor = hintColor
        symbol.verticalAlignmentMode = .center
        symbol.horizontalAlignmentMode = .center
        symbol.position = CGPoint(
            x: targetPosition.x + cellSide * 0.30,
            y: targetPosition.y + cellSide * 0.30
        )
        symbol.zPosition = 10
        board.addChild(symbol)

        let callout = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        callout.text = activeHint.action == .place
            ? "Place a pebble in the marked cell."
            : "Remove the pebble from the marked cell."
        callout.fontSize = 13
        callout.fontColor = hintColor
        callout.horizontalAlignmentMode = .center
        callout.position = CGPoint(x: 0, y: -side / 2 - 28)
        callout.zPosition = 10
        board.addChild(callout)

        if !UIAccessibility.isReduceMotionEnabled {
            ring.run(
                .repeatForever(
                    .sequence([
                        .fadeAlpha(to: 0.42, duration: 0.55),
                        .fadeAlpha(to: 1.0, duration: 0.55)
                    ])
                )
            )
        }
    }

    private var tutorialGuidanceText: String {
        switch levelIndex {
        case 0:
            return "Try the glowing cell."
        case 1:
            return "Find the row and column still missing a pebble."
        case 2:
            return "Look for a territory with no pebble yet."
        case 3:
            return "Keep the next pebble away from its neighbors."
        default:
            return "Use row, column, territory and spacing together."
        }
    }

    private func boardPosition(
        for coordinate: BoardCoordinate,
        cellSide: CGFloat,
        half: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: (CGFloat(coordinate.column) - half) * cellSide,
            y: (half - CGFloat(coordinate.row)) * cellSide
        )
    }

    private func animatePlacement(at coordinate: BoardCoordinate) {
        guard !UIAccessibility.isReduceMotionEnabled,
              let board = childNode(withName: "board") else {
            return
        }

        let name = cellName(for: coordinate)
        guard let pebble = board.children.last(where: {
            $0.name == name && $0.zPosition >= 3
        }) else {
            return
        }

        pebble.setScale(0.72)
        pebble.alpha = 0.55
        pebble.run(
            .group([
                .fadeIn(withDuration: 0.10),
                .sequence([
                    .scale(to: 1.08, duration: 0.10),
                    .scale(to: 0.98, duration: 0.08),
                    .scale(to: 1.0, duration: 0.08)
                ])
            ])
        )
    }

    private func animateConflict(at coordinate: BoardCoordinate) {
        guard !UIAccessibility.isReduceMotionEnabled,
              let board = childNode(withName: "board") else {
            return
        }

        let name = cellName(for: coordinate)
        let nodes = board.children.filter { $0.name == name }
        let shake = SKAction.sequence([
            .moveBy(x: -5, y: 0, duration: 0.045),
            .moveBy(x: 10, y: 0, duration: 0.075),
            .moveBy(x: -8, y: 0, duration: 0.065),
            .moveBy(x: 3, y: 0, duration: 0.045)
        ])
        nodes.forEach { $0.run(shake) }
    }

    private func makePebble(
        diameter: CGFloat,
        isConflicting: Bool
    ) -> SKNode {
        let root = SKNode()

        let contactShadow = SKShapeNode(
            ellipseOf: CGSize(width: diameter * 0.74, height: diameter * 0.32)
        )
        contactShadow.fillColor = inkColor.withAlphaComponent(0.18)
        contactShadow.strokeColor = .clear
        contactShadow.position = CGPoint(x: 0, y: -diameter * 0.27)
        contactShadow.zPosition = -1
        root.addChild(contactShadow)

        let body = SKShapeNode(path: pebblePath(diameter: diameter))
        body.fillColor = inkColor
        body.strokeColor = isConflicting
            ? warningColor
            : SKColor.white.withAlphaComponent(0.16)
        body.lineWidth = isConflicting ? 3.2 : 1
        root.addChild(body)

        let highlight = SKShapeNode(
            ellipseOf: CGSize(width: diameter * 0.18, height: diameter * 0.12)
        )
        highlight.fillColor = SKColor.white.withAlphaComponent(0.42)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(
            x: -diameter * 0.12,
            y: diameter * 0.16
        )
        highlight.zRotation = -0.4
        root.addChild(highlight)

        if isConflicting {
            let ring = SKShapeNode(
                ellipseOf: CGSize(width: diameter * 1.26, height: diameter * 1.26)
            )
            ring.fillColor = .clear
            ring.strokeColor = warningColor.withAlphaComponent(0.86)
            ring.lineWidth = 2
            ring.glowWidth = 1
            ring.zPosition = -0.5
            root.addChild(ring)
        }

        return root
    }

    private func pebblePath(diameter: CGFloat) -> CGPath {
        let radius = diameter / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: radius))
        path.addCurve(
            to: CGPoint(x: radius * 0.88, y: radius * 0.05),
            control1: CGPoint(x: radius * 0.52, y: radius * 0.92),
            control2: CGPoint(x: radius * 0.90, y: radius * 0.52)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: -radius * 0.92),
            control1: CGPoint(x: radius * 0.82, y: -radius * 0.46),
            control2: CGPoint(x: radius * 0.44, y: -radius * 0.90)
        )
        path.addCurve(
            to: CGPoint(x: -radius * 0.88, y: radius * 0.05),
            control1: CGPoint(x: -radius * 0.44, y: -radius * 0.90),
            control2: CGPoint(x: -radius * 0.82, y: -radius * 0.46)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: radius),
            control1: CGPoint(x: -radius * 0.90, y: radius * 0.52),
            control2: CGPoint(x: -radius * 0.52, y: radius * 0.92)
        )
        path.closeSubpath()
        return path
    }

    private func addFooter() {
        let footerY = max(68, size.height * 0.12)
        let settings = feedbackPreferences.current

        if !tutorialSession.isActive || playMode == .daily {
            let dailyTitle = playMode == .daily
                ? "Back to levels"
                : "Daily · \(progress.streak.currentCount)"
            let daily = makeButton(
                title: dailyTitle,
                name: NodeName.daily,
                width: 126
            )
            daily.position = CGPoint(x: size.width / 2, y: footerY + 52)
            addChild(daily)
        }

        let controls: [(String, String, CGFloat, CGFloat)] = [
            (settings.soundEnabled ? "Sound" : "Muted", NodeName.sound, 72, 0.10),
            (moveHistory.canUndo ? "Undo" : "Undo", NodeName.undo, 68, 0.30),
            ("Reset", NodeName.reset, 68, 0.50),
            (activeHint == nil ? "Hint" : "Hint ✓", NodeName.hint, 68, 0.70),
            (settings.hapticsEnabled ? "Haptic" : "No Hap", NodeName.haptics, 72, 0.90)
        ]

        for control in controls {
            let button = makeButton(
                title: control.0,
                name: control.1,
                width: control.2
            )
            button.position = CGPoint(
                x: size.width * control.3,
                y: footerY
            )
            if control.1 == NodeName.undo && !moveHistory.canUndo {
                button.alpha = 0.38
            }
            addChild(button)
        }

        let kit = SKLabelNode(fontNamed: "AvenirNext-Medium")
        kit.text = "GameTimeKit \(GameTimeKit.version)"
        kit.fontSize = 10
        kit.fontColor = inkColor.withAlphaComponent(0.28)
        kit.horizontalAlignmentMode = .center
        kit.position = CGPoint(x: size.width / 2, y: 26)
        addChild(kit)
    }

    private func makeButton(
        title: String,
        name: String,
        width: CGFloat = 116
    ) -> SKNode {
        let root = SKNode()
        root.name = name

        let shape = SKShapeNode(
            rectOf: CGSize(width: width, height: 42),
            cornerRadius: 21
        )
        shape.name = name
        shape.fillColor = inkColor.withAlphaComponent(0.07)
        shape.strokeColor = inkColor.withAlphaComponent(0.10)
        shape.lineWidth = 1
        root.addChild(shape)

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.name = name
        label.text = title
        label.fontSize = 12
        label.fontColor = inkColor.withAlphaComponent(0.78)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        root.addChild(label)

        return root
    }

    private func presentCompletion() {
        guard let board = childNode(withName: "board") else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        if !reduceMotion {
            let cells = board.children.filter {
                $0.name?.hasPrefix(NodeName.cellPrefix) == true
            }

            for (index, cell) in cells.enumerated() {
                let delay = Double(index % max(1, currentLevel.definition.size)) * 0.025
                cell.run(
                    .sequence([
                        .wait(forDuration: delay),
                        .scale(to: 1.045, duration: 0.10),
                        .scale(to: 1.0, duration: 0.18)
                    ])
                )
            }
        }

        let badge = SKShapeNode(
            rectOf: CGSize(width: min(280, size.width - 56), height: 118),
            cornerRadius: 28
        )
        badge.fillColor = canvasColor.withAlphaComponent(0.97)
        badge.strokeColor = SKColor.white.withAlphaComponent(0.8)
        badge.lineWidth = 1
        badge.position = CGPoint(x: size.width / 2, y: size.height * 0.51)
        badge.zPosition = 20
        badge.setScale(reduceMotion ? 1.0 : 0.84)
        badge.alpha = reduceMotion ? 1.0 : 0
        addChild(badge)

        let solved = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        if playMode == .daily {
            solved.text = "Daily complete · Streak \(progress.streak.currentCount)"
        } else {
            solved.text = levelIndex == levels.count - 1
                ? "Pack complete"
                : "Beautiful."
        }
        solved.fontSize = playMode == .daily ? 18 : 23
        solved.fontColor = inkColor
        solved.position = CGPoint(x: 0, y: 14)
        solved.verticalAlignmentMode = .center
        badge.addChild(solved)

        let nextTitle: String
        if playMode == .daily {
            nextTitle = "Back to levels"
        } else if levelIndex == levels.count - 1 {
            nextTitle = "Play again"
        } else {
            nextTitle = "Next puzzle"
        }
        let next = makeButton(title: nextTitle, name: NodeName.next)
        next.position = CGPoint(x: 0, y: -30)
        next.setScale(0.88)
        badge.addChild(next)

        if !reduceMotion {
            badge.run(
                .group([
                    .fadeIn(withDuration: 0.18),
                    .scale(to: 1.0, duration: 0.28)
                ])
            )
        }
    }

    private func recordGameplayIntent(
        kind: NineGameplayIntentKind,
        coordinate: BoardCoordinate? = nil
    ) {
        emittedGameplayIntents.append(
            NineGameplayIntent(
                kind: kind,
                levelID: currentLevel.definition.id,
                coordinate: coordinate
            )
        )
        if emittedGameplayIntents.count > 200 {
            emittedGameplayIntents.removeFirst(
                emittedGameplayIntents.count - 200
            )
        }

        #if DEBUG
        print("[NineIntent] \(kind.rawValue) \(coordinate.map(String.init(describing:)) ?? "-")")
        #endif
    }

    private func emitTutorialEvents(_ events: [NineTutorialEvent]) {
        guard !events.isEmpty else { return }

        emittedTutorialEvents.append(contentsOf: events)
        if emittedTutorialEvents.count > 100 {
            emittedTutorialEvents.removeFirst(emittedTutorialEvents.count - 100)
        }

        #if DEBUG
        for event in events {
            print("[NineTutorial] \(event.name) \(event.properties)")
        }
        #endif
    }

    private func cellName(for coordinate: BoardCoordinate) -> String {
        "\(NodeName.cellPrefix)\(coordinate.row):\(coordinate.column)"
    }

    private func coordinate(from nodeName: String?) -> BoardCoordinate? {
        guard let nodeName,
              nodeName.hasPrefix(NodeName.cellPrefix) else {
            return nil
        }

        let values = nodeName
            .dropFirst(NodeName.cellPrefix.count)
            .split(separator: ":")
        guard values.count == 2,
              let row = Int(values[0]),
              let column = Int(values[1]) else {
            return nil
        }
        return BoardCoordinate(row: row, column: column)
    }
}

private extension SKColor {
    static func nine(hex: UInt32, alpha: CGFloat = 1) -> SKColor {
        SKColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
