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

    #expect(
        state.toggleMarker(
            at: .init(row: 6, column: 0),
            level: level
        ) == false
    )
    #expect(state.markers.isEmpty)
}

@Test func placeToggleAndRemoveBehavePredictably() throws {
    let level = try rowRegions(size: 6)
    let coordinate = BoardCoordinate(row: 2, column: 4)
    var state = NineBoardState(level: level)

    #expect(state.placeMarker(at: coordinate, level: level))
    #expect(!state.placeMarker(at: coordinate, level: level))
    #expect(state.markers == [coordinate])

    #expect(state.toggleMarker(at: coordinate, level: level))
    #expect(state.markers.isEmpty)

    #expect(!state.removeMarker(at: coordinate))
}

@Test func detectsRowColumnAndRegionConflictsTogether() throws {
    let level = try rowRegions(size: 6)
    var state = NineBoardState(level: level)

    state.placeMarker(at: .init(row: 0, column: 0), level: level)
    state.placeMarker(at: .init(row: 0, column: 1), level: level)
    state.placeMarker(at: .init(row: 1, column: 0), level: level)

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

    state.placeMarker(at: .init(row: 0, column: 0), level: level)
    state.placeMarker(at: .init(row: 1, column: 1), level: level)

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

    state.placeMarker(at: .init(row: 0, column: 0), level: level)
    state.placeMarker(at: .init(row: 1, column: 1), level: level)

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

    #expect(
        !state.placeMarker(
            at: .init(row: 0, column: 0),
            level: second
        )
    )
    #expect(!NineConstraintEngine.evaluate(state, level: second).isSolved)
}
