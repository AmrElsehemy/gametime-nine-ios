import Foundation

enum ExactlyOneLevelKind: String, Codable, Sendable {
    case onboarding
    case standard
}

struct ExactlyOneLevelRecord: Codable, Equatable, Sendable {
    let id: String
    let order: Int
    let kind: ExactlyOneLevelKind
    let size: Int
    let regionIDs: [Int]
    let adjacencyRule: AdjacencyRule
    let initialMarkers: [BoardCoordinate]
    let solution: [BoardCoordinate]
    let difficulty: Int
    let authoringSeed: Int?
    var focusTuning: ExactlyOneFocusTuning? = nil

    func makeDefinition() throws -> LevelDefinition {
        try LevelDefinition(
            schemaVersion: 1,
            id: id,
            size: size,
            regionIDs: regionIDs,
            adjacencyRule: adjacencyRule
        )
    }

    func materialize() throws -> PrototypeLevel {
        let definition = try makeDefinition()
        let tuning = focusTuning ?? .initial(size: size, difficulty: difficulty)
        guard tuning.isValid else { throw ExactlyOneLevelPackError.malformedLevel(levelID: id, reason: "Invalid Focus Clock tuning") }
        return PrototypeLevel(
            definition: definition,
            initialMarkers: Set(initialMarkers),
            solution: solution,
            focusTuning: tuning
        )
    }
}

struct ExactlyOneLevelPack: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let levels: [ExactlyOneLevelRecord]
}

enum ExactlyOneLevelPackError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingResource(String)
    case unsupportedSchemaVersion(Int)
    case duplicateLevelID(String)
    case duplicateOrder(Int)
    case invalidDifficulty(levelID: String, value: Int)
    case invalidInitialMarker(levelID: String, coordinate: BoardCoordinate)
    case invalidAuthoredSolution(levelID: String)
    case unsolvable(levelID: String)
    case ambiguous(levelID: String)
    case malformedLevel(levelID: String, reason: String)

    var description: String {
        switch self {
        case .missingResource(let name):
            return "Missing bundled level resource: \(name)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported level-pack schema version: \(version)"
        case .duplicateLevelID(let id):
            return "Duplicate level id: \(id)"
        case .duplicateOrder(let order):
            return "Duplicate level order: \(order)"
        case .invalidDifficulty(let levelID, let value):
            return "Invalid difficulty \(value) for level \(levelID); expected 1...5"
        case .invalidInitialMarker(let levelID, let coordinate):
            return "Initial marker \(coordinate) is not part of the authored solution for level \(levelID)"
        case .invalidAuthoredSolution(let levelID):
            return "Authored solution does not satisfy all constraints for level \(levelID)"
        case .unsolvable(let levelID):
            return "Level \(levelID) has no solution"
        case .ambiguous(let levelID):
            return "Level \(levelID) has multiple solutions"
        case .malformedLevel(let levelID, let reason):
            return "Malformed level \(levelID): \(reason)"
        }
    }
}

enum ExactlyOneSolutionMultiplicity: String, Equatable, Sendable {
    case none
    case unique
    case multiple = "2+"
}

struct ExactlyOneSolverMetrics: Equatable, Sendable {
    var visitedNodes: Int = 0
    var backtracks: Int = 0
    var maxBranching: Int = 0
}

struct ExactlyOneSolverResult: Equatable, Sendable {
    let multiplicity: ExactlyOneSolutionMultiplicity
    let firstSolution: [BoardCoordinate]?
    let metrics: ExactlyOneSolverMetrics

    var hasUniqueSolution: Bool { multiplicity == .unique }
}

enum ExactlyOneLevelSolver {
    static func solve(
        definition: LevelDefinition,
        initialMarkers: Set<BoardCoordinate> = []
    ) -> ExactlyOneSolverResult {
        var metrics = ExactlyOneSolverMetrics()
        var solutions: [[BoardCoordinate]] = []

        guard initialStateIsConsistent(
            definition: definition,
            markers: initialMarkers
        ) else {
            return ExactlyOneSolverResult(
                multiplicity: .none,
                firstSolution: nil,
                metrics: metrics
            )
        }

        var placementsByRow: [Int: BoardCoordinate] = [:]
        var usedColumns = Set<Int>()
        var usedRegions = Set<Int>()

        for marker in initialMarkers.sorted() {
            placementsByRow[marker.row] = marker
            usedColumns.insert(marker.column)
            if let region = definition.regionID(at: marker) {
                usedRegions.insert(region)
            }
        }

        search(
            definition: definition,
            placementsByRow: &placementsByRow,
            usedColumns: &usedColumns,
            usedRegions: &usedRegions,
            solutions: &solutions,
            metrics: &metrics
        )

        let multiplicity: ExactlyOneSolutionMultiplicity
        switch solutions.count {
        case 0: multiplicity = .none
        case 1: multiplicity = .unique
        default: multiplicity = .multiple
        }

        return ExactlyOneSolverResult(
            multiplicity: multiplicity,
            firstSolution: solutions.first,
            metrics: metrics
        )
    }

    private static func search(
        definition: LevelDefinition,
        placementsByRow: inout [Int: BoardCoordinate],
        usedColumns: inout Set<Int>,
        usedRegions: inout Set<Int>,
        solutions: inout [[BoardCoordinate]],
        metrics: inout ExactlyOneSolverMetrics
    ) {
        guard solutions.count < 2 else { return }

        if placementsByRow.count == definition.size {
            solutions.append(
                placementsByRow.values.sorted()
            )
            return
        }

        let unresolvedRows = (0..<definition.size).filter {
            placementsByRow[$0] == nil
        }

        var selectedRow: Int?
        var selectedCandidates: [BoardCoordinate] = []

        for row in unresolvedRows {
            let candidates = candidatesForRow(
                row,
                definition: definition,
                placementsByRow: placementsByRow,
                usedColumns: usedColumns,
                usedRegions: usedRegions
            )

            if candidates.isEmpty {
                metrics.backtracks += 1
                return
            }

            // Rows are visited in ascending order, so ties keep the lowest row.
            if selectedRow == nil || candidates.count < selectedCandidates.count {
                selectedRow = row
                selectedCandidates = candidates
            }
        }

        guard let row = selectedRow else { return }
        metrics.maxBranching = max(metrics.maxBranching, selectedCandidates.count)

        for candidate in selectedCandidates {
            guard solutions.count < 2 else { return }
            metrics.visitedNodes += 1

            guard let region = definition.regionID(at: candidate) else {
                continue
            }

            placementsByRow[row] = candidate
            usedColumns.insert(candidate.column)
            usedRegions.insert(region)

            let hasFutureDeadEnd = (0..<definition.size)
                .filter { placementsByRow[$0] == nil }
                .contains { unresolvedRow in
                    candidatesForRow(
                        unresolvedRow,
                        definition: definition,
                        placementsByRow: placementsByRow,
                        usedColumns: usedColumns,
                        usedRegions: usedRegions
                    ).isEmpty
                }

            if hasFutureDeadEnd {
                metrics.backtracks += 1
            } else {
                search(
                    definition: definition,
                    placementsByRow: &placementsByRow,
                    usedColumns: &usedColumns,
                    usedRegions: &usedRegions,
                    solutions: &solutions,
                    metrics: &metrics
                )
            }

            placementsByRow.removeValue(forKey: row)
            usedColumns.remove(candidate.column)
            usedRegions.remove(region)
        }
    }

    private static func candidatesForRow(
        _ row: Int,
        definition: LevelDefinition,
        placementsByRow: [Int: BoardCoordinate],
        usedColumns: Set<Int>,
        usedRegions: Set<Int>
    ) -> [BoardCoordinate] {
        (0..<definition.size).compactMap { column in
            guard !usedColumns.contains(column) else { return nil }

            let coordinate = BoardCoordinate(row: row, column: column)
            guard let region = definition.regionID(at: coordinate),
                  !usedRegions.contains(region) else {
                return nil
            }

            if definition.adjacencyRule == .noTouching {
                let touchesExisting = placementsByRow.values.contains { existing in
                    abs(existing.row - coordinate.row) <= 1
                        && abs(existing.column - coordinate.column) <= 1
                }
                guard !touchesExisting else { return nil }
            }

            return coordinate
        }
    }

    private static func initialStateIsConsistent(
        definition: LevelDefinition,
        markers: Set<BoardCoordinate>
    ) -> Bool {
        guard markers.allSatisfy(definition.contains) else { return false }

        let state = ExactlyOneBoardState(level: definition, markers: markers)
        let evaluation = ExactlyOneConstraintEngine.evaluate(state, level: definition)
        guard evaluation.violations.isEmpty else { return false }

        return Set(markers.map(\.row)).count == markers.count
            && Set(markers.map(\.column)).count == markers.count
            && Set(markers.compactMap(definition.regionID)).count == markers.count
    }
}

struct ExactlyOneValidatedLevel: Sendable {
    let record: ExactlyOneLevelRecord
    let level: PrototypeLevel
    let solver: ExactlyOneSolverResult
}

enum ExactlyOneLevelPackValidator {
    static func validate(_ pack: ExactlyOneLevelPack) throws -> [ExactlyOneValidatedLevel] {
        guard pack.schemaVersion == 1 else {
            throw ExactlyOneLevelPackError.unsupportedSchemaVersion(pack.schemaVersion)
        }

        var ids = Set<String>()
        var orders = Set<Int>()
        var validated: [ExactlyOneValidatedLevel] = []

        for record in pack.levels.sorted(by: { $0.order < $1.order }) {
            guard ids.insert(record.id).inserted else {
                throw ExactlyOneLevelPackError.duplicateLevelID(record.id)
            }
            guard orders.insert(record.order).inserted else {
                throw ExactlyOneLevelPackError.duplicateOrder(record.order)
            }
            guard (1...5).contains(record.difficulty) else {
                throw ExactlyOneLevelPackError.invalidDifficulty(
                    levelID: record.id,
                    value: record.difficulty
                )
            }

            let level: PrototypeLevel
            do {
                level = try record.materialize()
            } catch {
                throw ExactlyOneLevelPackError.malformedLevel(
                    levelID: record.id,
                    reason: String(describing: error)
                )
            }

            let solutionSet = Set(record.solution)
            for marker in record.initialMarkers where !solutionSet.contains(marker) {
                throw ExactlyOneLevelPackError.invalidInitialMarker(
                    levelID: record.id,
                    coordinate: marker
                )
            }

            let authoredState = ExactlyOneBoardState(
                level: level.definition,
                markers: solutionSet
            )
            guard ExactlyOneConstraintEngine.evaluate(
                authoredState,
                level: level.definition
            ).isSolved else {
                throw ExactlyOneLevelPackError.invalidAuthoredSolution(levelID: record.id)
            }

            let solver = ExactlyOneLevelSolver.solve(
                definition: level.definition,
                initialMarkers: level.initialMarkers
            )

            switch solver.multiplicity {
            case .none:
                throw ExactlyOneLevelPackError.unsolvable(levelID: record.id)
            case .multiple:
                throw ExactlyOneLevelPackError.ambiguous(levelID: record.id)
            case .unique:
                break
            }

            guard Set(solver.firstSolution ?? []) == solutionSet else {
                throw ExactlyOneLevelPackError.invalidAuthoredSolution(levelID: record.id)
            }

            validated.append(
                ExactlyOneValidatedLevel(
                    record: record,
                    level: level,
                    solver: solver
                )
            )
        }

        return validated
    }
}

enum ExactlyOneContentGate: Int, CaseIterable, Sendable {
    case day3 = 20
    case testFlight = 50
    case submission = 60
    case v1Target = 100

    func isSatisfied(by count: Int) -> Bool {
        count >= rawValue
    }
}

enum ExactlyOneLevelCatalog {
    static let resourceName = "ExactlyOneLevels-v1"

    static func decode(data: Data) throws -> ExactlyOneLevelPack {
        let decoder = JSONDecoder()
        return try decoder.decode(ExactlyOneLevelPack.self, from: data)
    }

    static func loadBundled(
        bundle: Bundle = .main
    ) throws -> ExactlyOneLevelPack {
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: "json"
        ) else {
            throw ExactlyOneLevelPackError.missingResource("\(resourceName).json")
        }
        return try decode(data: Data(contentsOf: url))
    }

    static func validatedBundled(
        bundle: Bundle = .main
    ) throws -> [ExactlyOneValidatedLevel] {
        try ExactlyOneLevelPackValidator.validate(loadBundled(bundle: bundle))
    }
}
