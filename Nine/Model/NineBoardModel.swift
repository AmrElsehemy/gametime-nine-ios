import Foundation

/// Zero-based logical position on a Nine board.
struct BoardCoordinate: Hashable, Codable, Sendable, Comparable {
    let row: Int
    let column: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
    }
}

enum AdjacencyRule: String, Codable, Sendable {
    case none
    case noTouching
}

enum LevelDefinitionError: Error, Equatable, Sendable {
    case unsupportedSize(Int)
    case invalidRegionMap(expected: Int, actual: Int)
    case invalidRegionCount(expected: Int, actual: Int)
}

/// Framework-independent, versioned description of one puzzle board.
struct LevelDefinition: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let size: Int
    /// Row-major region identifier for every cell.
    let regionIDs: [Int]
    let adjacencyRule: AdjacencyRule

    init(
        schemaVersion: Int = 1,
        id: String,
        size: Int,
        regionIDs: [Int],
        adjacencyRule: AdjacencyRule = .noTouching
    ) throws {
        guard (6...9).contains(size) else {
            throw LevelDefinitionError.unsupportedSize(size)
        }

        let expectedCellCount = size * size
        guard regionIDs.count == expectedCellCount else {
            throw LevelDefinitionError.invalidRegionMap(
                expected: expectedCellCount,
                actual: regionIDs.count
            )
        }

        let regionCount = Set(regionIDs).count
        guard regionCount == size else {
            throw LevelDefinitionError.invalidRegionCount(
                expected: size,
                actual: regionCount
            )
        }

        self.schemaVersion = schemaVersion
        self.id = id
        self.size = size
        self.regionIDs = regionIDs
        self.adjacencyRule = adjacencyRule
    }

    func contains(_ coordinate: BoardCoordinate) -> Bool {
        (0..<size).contains(coordinate.row)
            && (0..<size).contains(coordinate.column)
    }

    func regionID(at coordinate: BoardCoordinate) -> Int? {
        guard contains(coordinate) else { return nil }
        return regionIDs[coordinate.row * size + coordinate.column]
    }
}

/// Player-owned logical state. No SpriteKit/UI types are allowed here.
struct NineBoardState: Equatable, Sendable {
    let levelID: String
    let levelSchemaVersion: Int
    private(set) var markers: Set<BoardCoordinate>

    init(level: LevelDefinition, markers: Set<BoardCoordinate> = []) {
        self.levelID = level.id
        self.levelSchemaVersion = level.schemaVersion
        self.markers = Set(markers.filter(level.contains))
    }

    @discardableResult
    mutating func toggleMarker(
        at coordinate: BoardCoordinate,
        level: LevelDefinition
    ) -> Bool {
        guard isCompatible(with: level), level.contains(coordinate) else {
            return false
        }

        if markers.remove(coordinate) != nil {
            return true
        }

        markers.insert(coordinate)
        return true
    }

    @discardableResult
    mutating func placeMarker(
        at coordinate: BoardCoordinate,
        level: LevelDefinition
    ) -> Bool {
        guard isCompatible(with: level), level.contains(coordinate) else {
            return false
        }
        return markers.insert(coordinate).inserted
    }

    @discardableResult
    mutating func removeMarker(at coordinate: BoardCoordinate) -> Bool {
        markers.remove(coordinate) != nil
    }

    private func isCompatible(with level: LevelDefinition) -> Bool {
        level.id == levelID && level.schemaVersion == levelSchemaVersion
    }
}

// Encode marker order deterministically so logical state is suitable for
// repeatable fixtures, diagnostics, and later replay hashing.
extension NineBoardState: Codable {
    private enum CodingKeys: String, CodingKey {
        case levelID
        case levelSchemaVersion
        case markers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        levelID = try container.decode(String.self, forKey: .levelID)
        levelSchemaVersion = try container.decode(Int.self, forKey: .levelSchemaVersion)
        markers = Set(try container.decode([BoardCoordinate].self, forKey: .markers))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(levelID, forKey: .levelID)
        try container.encode(levelSchemaVersion, forKey: .levelSchemaVersion)
        try container.encode(markers.sorted(), forKey: .markers)
    }
}

enum ConstraintViolationKind: String, Codable, Sendable {
    case row
    case column
    case region
    case adjacency
}

/// Concrete conflict metadata that the renderer can translate into visual feedback.
struct ConstraintViolation: Codable, Equatable, Sendable {
    let kind: ConstraintViolationKind
    let coordinates: [BoardCoordinate]
    /// Row, column, or region ID where applicable. Nil for pairwise adjacency.
    let index: Int?

    init(
        kind: ConstraintViolationKind,
        coordinates: [BoardCoordinate],
        index: Int? = nil
    ) {
        self.kind = kind
        self.coordinates = coordinates.sorted()
        self.index = index
    }
}

struct BoardEvaluation: Codable, Equatable, Sendable {
    let violations: [ConstraintViolation]
    let isSolved: Bool

    var conflictingCoordinates: Set<BoardCoordinate> {
        Set(violations.flatMap(\.coordinates))
    }
}

enum NineConstraintEngine {
    static func evaluate(
        _ state: NineBoardState,
        level: LevelDefinition
    ) -> BoardEvaluation {
        guard state.levelID == level.id,
              state.levelSchemaVersion == level.schemaVersion else {
            return BoardEvaluation(violations: [], isSolved: false)
        }

        let markers = state.markers.sorted()
        var violations: [ConstraintViolation] = []

        for row in 0..<level.size {
            let matches = markers.filter { $0.row == row }
            if matches.count > 1 {
                violations.append(
                    .init(kind: .row, coordinates: matches, index: row)
                )
            }
        }

        for column in 0..<level.size {
            let matches = markers.filter { $0.column == column }
            if matches.count > 1 {
                violations.append(
                    .init(kind: .column, coordinates: matches, index: column)
                )
            }
        }

        var coordinatesByRegion: [Int: [BoardCoordinate]] = [:]
        for marker in markers {
            guard let regionID = level.regionID(at: marker) else { continue }
            coordinatesByRegion[regionID, default: []].append(marker)
        }

        for regionID in coordinatesByRegion.keys.sorted() {
            let matches = coordinatesByRegion[regionID, default: []]
            if matches.count > 1 {
                violations.append(
                    .init(kind: .region, coordinates: matches, index: regionID)
                )
            }
        }

        if level.adjacencyRule == .noTouching {
            for firstIndex in markers.indices {
                for secondIndex in markers.index(after: firstIndex)..<markers.endIndex {
                    let lhs = markers[firstIndex]
                    let rhs = markers[secondIndex]
                    let rowDelta = abs(lhs.row - rhs.row)
                    let columnDelta = abs(lhs.column - rhs.column)

                    if rowDelta <= 1 && columnDelta <= 1 {
                        violations.append(
                            .init(kind: .adjacency, coordinates: [lhs, rhs])
                        )
                    }
                }
            }
        }

        let rowsCovered = Set(markers.map(\.row)).count == level.size
        let columnsCovered = Set(markers.map(\.column)).count == level.size
        let regionCount = Set(level.regionIDs).count
        let regionsCovered = Set(markers.compactMap(level.regionID)).count == regionCount

        let isSolved = markers.count == level.size
            && rowsCovered
            && columnsCovered
            && regionsCovered
            && violations.isEmpty

        return BoardEvaluation(
            violations: violations,
            isSolved: isSolved
        )
    }
}

// MARK: - Temporary vertical-slice content

/// In-code content used only to make issue #5 playable end-to-end. The
/// production level pipeline in issue #7 replaces this catalogue with
/// versioned bundled data, validation, and solver-backed authoring.
struct PrototypeLevel: Sendable {
    let definition: LevelDefinition
    let initialMarkers: Set<BoardCoordinate>
    let solution: [BoardCoordinate]

    init(
        id: String,
        size: Int,
        regionIDs: [Int],
        solutionColumns: [Int],
        prefilledCount: Int
    ) {
        precondition(solutionColumns.count == size)

        let solution = solutionColumns.enumerated().map {
            BoardCoordinate(row: $0.offset, column: $0.element)
        }

        self.definition = try! LevelDefinition(
            id: id,
            size: size,
            regionIDs: regionIDs,
            adjacencyRule: .noTouching
        )
        self.solution = solution
        self.initialMarkers = Set(solution.prefix(prefilledCount))
    }
}

enum PrototypeLevels {
    static let all: [PrototypeLevel] = [
        PrototypeLevel(
            id: "prototype-001",
            size: 6,
            regionIDs: [
                0, 0, 0, 1, 1, 2,
                0, 0, 1, 1, 1, 2,
                3, 0, 1, 1, 2, 2,
                3, 3, 4, 1, 2, 2,
                3, 4, 4, 4, 5, 2,
                3, 4, 4, 5, 5, 5
            ],
            solutionColumns: [1, 3, 5, 0, 2, 4],
            prefilledCount: 5
        ),
        PrototypeLevel(
            id: "prototype-002",
            size: 6,
            regionIDs: [
                0, 0, 0, 0, 0, 1,
                2, 2, 0, 0, 1, 1,
                2, 2, 2, 2, 3, 1,
                4, 2, 2, 3, 3, 3,
                4, 4, 4, 5, 3, 3,
                4, 4, 5, 5, 5, 5
            ],
            solutionColumns: [2, 5, 1, 4, 0, 3],
            prefilledCount: 3
        ),
        PrototypeLevel(
            id: "prototype-003",
            size: 6,
            regionIDs: [
                1, 0, 0, 0, 0, 0,
                1, 1, 0, 0, 2, 2,
                1, 3, 2, 2, 2, 2,
                3, 3, 3, 2, 2, 4,
                3, 3, 5, 4, 4, 4,
                5, 5, 5, 5, 4, 4
            ],
            solutionColumns: [3, 0, 4, 1, 5, 2],
            prefilledCount: 2
        ),
        PrototypeLevel(
            id: "prototype-004",
            size: 6,
            regionIDs: [
                2, 1, 1, 0, 0, 0,
                2, 1, 1, 1, 0, 0,
                2, 2, 1, 1, 0, 3,
                2, 2, 1, 4, 3, 3,
                2, 5, 4, 4, 4, 3,
                5, 5, 5, 4, 4, 3
            ],
            solutionColumns: [4, 2, 0, 5, 3, 1],
            prefilledCount: 1
        ),
        PrototypeLevel(
            id: "prototype-005",
            size: 7,
            regionIDs: [
                0, 0, 1, 1, 2, 2, 3,
                0, 1, 1, 1, 2, 2, 3,
                0, 1, 1, 2, 2, 2, 3,
                4, 4, 1, 2, 2, 3, 3,
                4, 4, 4, 5, 2, 3, 3,
                4, 4, 5, 5, 5, 6, 3,
                4, 4, 5, 5, 6, 6, 6
            ],
            solutionColumns: [0, 2, 4, 6, 1, 3, 5],
            prefilledCount: 0
        )
    ]
}
