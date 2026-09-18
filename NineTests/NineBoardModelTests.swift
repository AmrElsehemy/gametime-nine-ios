import Foundation
import Testing
@testable import Nine

private func rowRegions(
    size: Int,
    adjacency: AdjacencyRule = .none
) throws -> LevelDefinition {
    try LevelDefinition(
        id: "test-\(size)",
        size: size,
        regionIDs: (0..<size).flatMap { row in
            Array(repeating: row, count: size)
        },
        adjacencyRule: adjacency
    )
}

@Test func levelDefinitionRejectsMalformedContent() throws {
    #expect(throws: LevelDefinitionError.unsupportedSize(5)) {
        _ = try LevelDefinition(
            id: "small",
            size: 5,
            regionIDs: Array(repeating: 0, count: 25)
        )
    }

    #expect(throws: LevelDefinitionError.invalidRegionMap(expected: 36, actual: 35)) {
        _ = try LevelDefinition(
            id: "bad-map",
            size: 6,
            regionIDs: Array(repeating: 0, count: 35)
        )
    }

    #expect(throws: LevelDefinitionError.invalidRegionCount(expected: 6, actual: 1)) {
        _ = try LevelDefinition(
            id: "bad-regions",
            size: 6,
            regionIDs: Array(repeating: 0, count: 36)
        )
    }
}

@Test func rejectsOutOfBoundsMutationWithoutCorruptingState() throws {
    let level = try rowRegions(size: 6)
    var state = NineBoardState(level: level)

    let didToggle = state.toggleMarker(
        at: .init(row: 6, column: 0),
        level: level
    )
    #expect(didToggle == false)
    #expect(state.markers.isEmpty)
}

@Test func placeToggleAndRemoveBehavePredictably() throws {
    let level = try rowRegions(size: 6)
    let coordinate = BoardCoordinate(row: 2, column: 4)
    var state = NineBoardState(level: level)

    let firstPlacement = state.placeMarker(at: coordinate, level: level)
    #expect(firstPlacement)

    let duplicatePlacement = state.placeMarker(at: coordinate, level: level)
    #expect(!duplicatePlacement)
    #expect(state.markers == [coordinate])

    let didToggle = state.toggleMarker(at: coordinate, level: level)
    #expect(didToggle)
    #expect(state.markers.isEmpty)

    let didRemove = state.removeMarker(at: coordinate)
    #expect(!didRemove)
}

@Test func detectsRowColumnAndRegionConflictsTogether() throws {
    let level = try rowRegions(size: 6)
    var state = NineBoardState(level: level)

    _ = state.placeMarker(at: .init(row: 0, column: 0), level: level)
    _ = state.placeMarker(at: .init(row: 0, column: 1), level: level)
    _ = state.placeMarker(at: .init(row: 1, column: 0), level: level)

    let evaluation = NineConstraintEngine.evaluate(state, level: level)

    #expect(evaluation.violations.contains { $0.kind == .row })
    #expect(evaluation.violations.contains { $0.kind == .column })
    #expect(evaluation.violations.contains { $0.kind == .region })
    #expect(evaluation.conflictingCoordinates.count == 3)
    #expect(!evaluation.isSolved)
}

@Test func detectsAdjacencyConflict() throws {
    let level = try rowRegions(size: 6, adjacency: .noTouching)
    var state = NineBoardState(level: level)

    _ = state.placeMarker(at: .init(row: 0, column: 0), level: level)
    _ = state.placeMarker(at: .init(row: 1, column: 1), level: level)

    let evaluation = NineConstraintEngine.evaluate(state, level: level)

    #expect(evaluation.violations.contains { $0.kind == .adjacency })
    #expect(
        evaluation.conflictingCoordinates
            == [
                BoardCoordinate(row: 0, column: 0),
                BoardCoordinate(row: 1, column: 1)
            ]
    )
}

@Test func adjacencyCanBeDisabledByLevelData() throws {
    let level = try rowRegions(size: 6, adjacency: .none)
    var state = NineBoardState(level: level)

    _ = state.placeMarker(at: .init(row: 0, column: 0), level: level)
    _ = state.placeMarker(at: .init(row: 1, column: 1), level: level)

    let evaluation = NineConstraintEngine.evaluate(state, level: level)
    #expect(!evaluation.violations.contains { $0.kind == .adjacency })
}

@Test func recognizesSolvedSixBySixBoard() throws {
    let level = try rowRegions(size: 6, adjacency: .none)
    let coordinates = Set(
        (0..<6).map { BoardCoordinate(row: $0, column: $0) }
    )
    let state = NineBoardState(level: level, markers: coordinates)

    #expect(NineConstraintEngine.evaluate(state, level: level).isSolved)
}

@Test func supportsNineByNineWithoutRuleChanges() throws {
    let level = try rowRegions(size: 9, adjacency: .none)

    #expect(level.size == 9)
    #expect(level.regionIDs.count == 81)

    let coordinates = Set(
        (0..<9).map { BoardCoordinate(row: $0, column: $0) }
    )
    let state = NineBoardState(level: level, markers: coordinates)
    #expect(NineConstraintEngine.evaluate(state, level: level).isSolved)
}

@Test func stateSerializationIsStableAndRoundTrips() throws {
    let level = try rowRegions(size: 6)
    let state = NineBoardState(
        level: level,
        markers: [
            .init(row: 5, column: 1),
            .init(row: 2, column: 4)
        ]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let firstEncoding = try encoder.encode(state)
    let secondEncoding = try encoder.encode(state)
    #expect(firstEncoding == secondEncoding)

    let decoded = try JSONDecoder().decode(
        NineBoardState.self,
        from: firstEncoding
    )
    #expect(decoded == state)
}

@Test func stateFromDifferentLevelCannotBeMutatedOrSolvedAgainstAnotherLevel() throws {
    let first = try rowRegions(size: 6)
    let second = try LevelDefinition(
        id: "another-level",
        size: 6,
        regionIDs: first.regionIDs,
        adjacencyRule: .none
    )
    var state = NineBoardState(level: first)

    let didPlace = state.placeMarker(
        at: .init(row: 0, column: 0),
        level: second
    )
    #expect(!didPlace)
    #expect(!NineConstraintEngine.evaluate(state, level: second).isSolved)
}

@Test func prototypeCatalogueContainsFivePlayableBoardsWithValidKnownSolutions() {
    #expect(PrototypeLevels.all.count == 5)

    for prototype in PrototypeLevels.all {
        let solutionState = NineBoardState(
            level: prototype.definition,
            markers: Set(prototype.solution)
        )
        let evaluation = NineConstraintEngine.evaluate(
            solutionState,
            level: prototype.definition
        )

        #expect(evaluation.isSolved)
        #expect(evaluation.violations.isEmpty)
        #expect(prototype.initialMarkers.isSubset(of: Set(prototype.solution)))
    }
}

@Test func tutorialEscalatesAtFourEightAndFifteenSeconds() {
    var session = NineTutorialSession(isActive: true)
    let started = session.beginLevel(index: 0, levelID: "tutorial-1", now: 100)

    #expect(started.map(\.name) == ["tutorial_started", "tutorial_level_started"])
    #expect(session.assistanceDue(levelID: "tutorial-1", now: 103.9).isEmpty)

    let subtle = session.assistanceDue(levelID: "tutorial-1", now: 104)
    #expect(session.currentAssistance == .subtle)
    #expect(subtle.first?.properties["trigger"] == "idle")

    _ = session.assistanceDue(levelID: "tutorial-1", now: 108)
    #expect(session.currentAssistance == .contextual)

    _ = session.assistanceDue(levelID: "tutorial-1", now: 115)
    #expect(session.currentAssistance == .strong)
}

@Test func validTutorialProgressResetsAssistanceAndInvalidCluster() {
    var session = NineTutorialSession(isActive: true)
    _ = session.beginLevel(index: 1, levelID: "tutorial-2", now: 0)
    _ = session.assistanceDue(levelID: "tutorial-2", now: 8)
    #expect(session.currentAssistance == .contextual)

    _ = session.recordInteraction(
        isValid: false,
        levelID: "tutorial-2",
        now: 8.5
    )
    #expect(session.invalidInteractionTimes.count == 1)

    let progress = session.recordInteraction(
        isValid: true,
        levelID: "tutorial-2",
        now: 9
    )

    #expect(progress.first?.name == "tutorial_interaction")
    #expect(session.currentAssistance == .none)
    #expect(session.invalidInteractionTimes.isEmpty)
    #expect(session.assistanceDue(levelID: "tutorial-2", now: 12.9).isEmpty)
}

@Test func repeatedInvalidInteractionsEscalateWithinSixSecondWindow() {
    var session = NineTutorialSession(isActive: true)
    _ = session.beginLevel(index: 3, levelID: "tutorial-4", now: 0)

    let first = session.recordInteraction(
        isValid: false,
        levelID: "tutorial-4",
        now: 1
    )
    #expect(first.count == 1)
    #expect(session.currentAssistance == .none)

    let second = session.recordInteraction(
        isValid: false,
        levelID: "tutorial-4",
        now: 2
    )
    #expect(session.currentAssistance == .contextual)
    #expect(second.last?.properties["trigger"] == "invalid_interactions")

    _ = session.recordInteraction(
        isValid: false,
        levelID: "tutorial-4",
        now: 3
    )
    #expect(session.currentAssistance == .strong)
}

@Test func tutorialCompletionDisablesHelpAndMonetizationSuppression() {
    var session = NineTutorialSession(isActive: true)
    _ = session.beginLevel(index: 4, levelID: "tutorial-5", now: 0)

    #expect(session.suppressesMonetization)

    let completed = session.complete(levelID: "tutorial-5")
    #expect(completed.first?.name == "tutorial_completed")
    #expect(!session.isActive)
    #expect(!session.suppressesMonetization)
    #expect(session.assistanceDue(levelID: "tutorial-5", now: 100).isEmpty)
}

@Test func tutorialCompletionStorePersistsAcrossInstances() throws {
    let suiteName = "NineTutorialCompletionStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = NineTutorialCompletionStore(defaults: defaults)
    #expect(!first.isComplete)
    first.markComplete()

    let second = NineTutorialCompletionStore(defaults: defaults)
    #expect(second.isComplete)
}
