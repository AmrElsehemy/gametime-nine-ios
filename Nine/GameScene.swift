import Foundation
import SpriteKit
import GameTimeCore
import GameTimeExperience

final class GameScene: SKScene {
    private enum NodeName {
        static let reset = "action:reset"
        static let next = "action:next"
        static let cellPrefix = "cell:"
    }

    private let canvasColor = SKColor.nine(hex: 0xF5F2EA)
    private let inkColor = SKColor.nine(hex: 0x262624)
    private let warningColor = SKColor.nine(hex: 0xC95555)
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

    private let tutorialStore = NineTutorialCompletionStore()
    private lazy var tutorialSession = NineTutorialSession(
        isActive: !tutorialStore.isComplete
    )
    private var emittedTutorialEvents: [NineTutorialEvent] = []

    private var levelIndex = 0
    private var boardState: NineBoardState?
    private var latestEvaluation = BoardEvaluation(violations: [], isSolved: false)
    private var isLevelComplete = false
    private var hasPresentedScene = false

    private var currentLevel: PrototypeLevel {
        PrototypeLevels.all[levelIndex]
    }

    private var uptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    override func didMove(to view: SKView) {
        backgroundColor = canvasColor
        view.ignoresSiblingOrder = true

        if boardState == nil {
            loadLevel(at: 0)
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
        guard tutorialSession.isActive, !isLevelComplete else { return }

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
        latestEvaluation = NineConstraintEngine.evaluate(
            state,
            level: currentLevel.definition
        )

        let placedMarker = !markerWasPresent && state.markers.contains(coordinate)
        let invalidPlacement = placedMarker
            && latestEvaluation.conflictingCoordinates.contains(coordinate)

        emitTutorialEvents(
            tutorialSession.recordInteraction(
                isValid: !invalidPlacement,
                levelID: currentLevel.definition.id,
                now: uptime
            )
        )

        if latestEvaluation.isSolved,
           levelIndex == PrototypeLevels.all.count - 1,
           tutorialSession.isActive {
            tutorialStore.markComplete()
            emitTutorialEvents(
                tutorialSession.complete(levelID: currentLevel.definition.id)
            )
        }

        renderScene()

        if latestEvaluation.isSolved {
            isLevelComplete = true
            presentCompletion()
        }
    }

    private func loadLevel(at index: Int) {
        levelIndex = max(0, min(index, PrototypeLevels.all.count - 1))
        let level = currentLevel
        boardState = NineBoardState(
            level: level.definition,
            markers: level.initialMarkers
        )
        latestEvaluation = boardState.map {
            NineConstraintEngine.evaluate($0, level: level.definition)
        } ?? .init(violations: [], isSolved: false)
        isLevelComplete = false

        emitTutorialEvents(
            tutorialSession.beginLevel(
                index: levelIndex,
                levelID: level.definition.id,
                now: uptime
            )
        )
        renderScene()
    }

    private func resetCurrentLevel() {
        let level = currentLevel
        let resetState = NineBoardState(
            level: level.definition,
            markers: level.initialMarkers
        )
        boardState = resetState
        latestEvaluation = NineConstraintEngine.evaluate(
            resetState,
            level: level.definition
        )
        isLevelComplete = false

        emitTutorialEvents(
            tutorialSession.recordInteraction(
                isValid: true,
                levelID: level.definition.id,
                now: uptime
            )
        )
        renderScene()
    }

    private func advanceLevel() {
        let nextIndex = levelIndex + 1
        loadLevel(at: nextIndex < PrototypeLevels.all.count ? nextIndex : 0)
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
        eyebrow.text = tutorialSession.isActive
            ? "LEARN BY PLAYING  ·  \(levelIndex + 1) / \(PrototypeLevels.all.count)"
            : "PUZZLE  \(levelIndex + 1) / \(PrototypeLevels.all.count)"
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
        guard tutorialSession.isActive else {
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

        return container
    }

    private func addTutorialGuidance(
        to board: SKNode,
        side: CGFloat,
        cellSide: CGFloat,
        half: CGFloat,
        state: NineBoardState
    ) {
        guard tutorialSession.isActive,
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

        let reset = makeButton(title: "Reset", name: NodeName.reset)
        reset.position = CGPoint(x: size.width / 2, y: footerY)
        addChild(reset)

        let kit = SKLabelNode(fontNamed: "AvenirNext-Medium")
        kit.text = "GameTimeKit \(GameTimeKit.version)"
        kit.fontSize = 10
        kit.fontColor = inkColor.withAlphaComponent(0.28)
        kit.horizontalAlignmentMode = .center
        kit.position = CGPoint(x: size.width / 2, y: 26)
        addChild(kit)
    }

    private func makeButton(title: String, name: String) -> SKNode {
        let root = SKNode()
        root.name = name

        let shape = SKShapeNode(
            rectOf: CGSize(width: 116, height: 42),
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
        label.fontSize = 14
        label.fontColor = inkColor.withAlphaComponent(0.78)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        root.addChild(label)

        return root
    }

    private func presentCompletion() {
        guard let board = childNode(withName: "board") else { return }

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

        let badge = SKShapeNode(
            rectOf: CGSize(width: min(280, size.width - 56), height: 118),
            cornerRadius: 28
        )
        badge.fillColor = canvasColor.withAlphaComponent(0.97)
        badge.strokeColor = SKColor.white.withAlphaComponent(0.8)
        badge.lineWidth = 1
        badge.position = CGPoint(x: size.width / 2, y: size.height * 0.51)
        badge.zPosition = 20
        badge.setScale(0.84)
        badge.alpha = 0
        addChild(badge)

        let solved = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        solved.text = levelIndex == PrototypeLevels.all.count - 1
            ? "Prototype complete"
            : "Beautiful."
        solved.fontSize = 23
        solved.fontColor = inkColor
        solved.position = CGPoint(x: 0, y: 14)
        solved.verticalAlignmentMode = .center
        badge.addChild(solved)

        let nextTitle = levelIndex == PrototypeLevels.all.count - 1
            ? "Play again"
            : "Next puzzle"
        let next = makeButton(title: nextTitle, name: NodeName.next)
        next.position = CGPoint(x: 0, y: -30)
        next.setScale(0.88)
        badge.addChild(next)

        badge.run(
            .group([
                .fadeIn(withDuration: 0.18),
                .scale(to: 1.0, duration: 0.28)
            ])
        )
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
