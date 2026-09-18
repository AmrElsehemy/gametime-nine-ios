import Foundation

enum NineLevelKind: String, Codable, Sendable {
    case onboarding
    case standard
}

struct NineLevelRecord: Codable, Equatable, Sendable {
    let id: String
    let order: Int
    let kind: NineLevelKind
    let size: Int
    let regionIDs: [Int]
    let adjacencyRule: AdjacencyRule
    let initialMarkers: [BoardCoordinate]
    let solution: [BoardCoordinate]
    let difficulty: Int
    let authoringSeed: Int?

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
        return PrototypeLevel(
            definition: definition,
            initialMarkers: Set(initialMarkers),
            solution: solution
        )
    }
}

struct NineLevelPack: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let levels: [NineLevelRecord]
}

enum NineLevelPackError: Error, Equatable, CustomStringConvertible, Sendable {
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

enum NineSolutionMultiplicity: String, Equatable, Sendable {
    case none
    case unique
    case multiple = "2+"
}

struct NineSolverMetrics: Equatable, Sendable {
    var visitedNodes: Int = 0
    var backtracks: Int = 0
    var maxBranching: Int = 0
}

struct NineSolverResult: Equatable, Sendable {
    let multiplicity: NineSolutionMultiplicity
    let firstSolution: [BoardCoordinate]?
    let metrics: NineSolverMetrics

    var hasUniqueSolution: Bool { multiplicity == .unique }
}

enum NineLevelSolver {
    static func solve(
        definition: LevelDefinition,
        initialMarkers: Set<BoardCoordinate> = []
    ) -> NineSolverResult {
        var metrics = NineSolverMetrics()
        var solutions: [[BoardCoordinate]] = []

        guard initialStateIsConsistent(
            definition: definition,
            markers: initialMarkers
        ) else {
            return NineSolverResult(
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

        let multiplicity: NineSolutionMultiplicity
        switch solutions.count {
        case 0: multiplicity = .none
        case 1: multiplicity = .unique
        default: multiplicity = .multiple
        }

        return NineSolverResult(
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
        metrics: inout NineSolverMetrics
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

            if selectedRow == nil
                || candidates.count < selectedCandidates.count
                || (candidates.count == selectedCandidates.count && row < selectedRow!) {
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

        let state = NineBoardState(level: definition, markers: markers)
        let evaluation = NineConstraintEngine.evaluate(state, level: definition)
        guard evaluation.violations.isEmpty else { return false }

        return Set(markers.map(\.row)).count == markers.count
            && Set(markers.map(\.column)).count == markers.count
            && Set(markers.compactMap(definition.regionID)).count == markers.count
    }
}

struct NineValidatedLevel: Sendable {
    let record: NineLevelRecord
    let level: PrototypeLevel
    let solver: NineSolverResult
}

enum NineLevelPackValidator {
    static func validate(_ pack: NineLevelPack) throws -> [NineValidatedLevel] {
        guard pack.schemaVersion == 1 else {
            throw NineLevelPackError.unsupportedSchemaVersion(pack.schemaVersion)
        }

        var ids = Set<String>()
        var orders = Set<Int>()
        var validated: [NineValidatedLevel] = []

        for record in pack.levels.sorted(by: { $0.order < $1.order }) {
            guard ids.insert(record.id).inserted else {
                throw NineLevelPackError.duplicateLevelID(record.id)
            }
            guard orders.insert(record.order).inserted else {
                throw NineLevelPackError.duplicateOrder(record.order)
            }
            guard (1...5).contains(record.difficulty) else {
                throw NineLevelPackError.invalidDifficulty(
                    levelID: record.id,
                    value: record.difficulty
                )
            }

            let level: PrototypeLevel
            do {
                level = try record.materialize()
            } catch {
                throw NineLevelPackError.malformedLevel(
                    levelID: record.id,
                    reason: String(describing: error)
                )
            }

            let solutionSet = Set(record.solution)
            for marker in record.initialMarkers where !solutionSet.contains(marker) {
                throw NineLevelPackError.invalidInitialMarker(
                    levelID: record.id,
                    coordinate: marker
                )
            }

            let authoredState = NineBoardState(
                level: level.definition,
                markers: solutionSet
            )
            guard NineConstraintEngine.evaluate(
                authoredState,
                level: level.definition
            ).isSolved else {
                throw NineLevelPackError.invalidAuthoredSolution(levelID: record.id)
            }

            let solver = NineLevelSolver.solve(
                definition: level.definition,
                initialMarkers: level.initialMarkers
            )

            switch solver.multiplicity {
            case .none:
                throw NineLevelPackError.unsolvable(levelID: record.id)
            case .multiple:
                throw NineLevelPackError.ambiguous(levelID: record.id)
            case .unique:
                break
            }

            guard Set(solver.firstSolution ?? []) == solutionSet else {
                throw NineLevelPackError.invalidAuthoredSolution(levelID: record.id)
            }

            validated.append(
                NineValidatedLevel(
                    record: record,
                    level: level,
                    solver: solver
                )
            )
        }

        return validated
    }
}

enum NineContentGate: Int, CaseIterable, Sendable {
    case day3 = 20
    case testFlight = 50
    case submission = 60
    case v1Target = 100

    func isSatisfied(by count: Int) -> Bool {
        count >= rawValue
    }
}

enum NineLevelCatalog {
    static let resourceName = "NineLevels-v1"

    static func decode(data: Data) throws -> NineLevelPack {
        let decoder = JSONDecoder()
        return try decoder.decode(NineLevelPack.self, from: data)
    }

    static func loadBundled(
        bundle: Bundle = .main
    ) throws -> NineLevelPack {
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: "json"
        ) else {
            throw NineLevelPackError.missingResource("\(resourceName).json")
        }
        return try decode(data: Data(contentsOf: url))
    }

    static func validatedBundled(
        bundle: Bundle = .main
    ) throws -> [NineValidatedLevel] {
        try NineLevelPackValidator.validate(loadBundled(bundle: bundle))
    }
}
