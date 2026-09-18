import Foundation
import Testing
@testable import Nine

@Test func solverDistinguishesMultipleSolutionsAndStopsAtTwo() throws {
    let definition = try LevelDefinition(
        id: "ambiguous",
        size: 6,
        regionIDs: (0..<6).flatMap { row in
            Array(repeating: row, count: 6)
        },
        adjacencyRule: .none
    )

    let result = NineLevelSolver.solve(definition: definition)

    #expect(result.multiplicity == .multiple)
    #expect(result.firstSolution != nil)
    #expect(result.metrics.visitedNodes > 0)
}

@Test func solverRejectsConflictingInitialState() throws {
    let definition = try LevelDefinition(
        id: "conflicting-clues",
        size: 6,
        regionIDs: (0..<6).flatMap { row in
            Array(repeating: row, count: 6)
        },
        adjacencyRule: .none
    )

    let result = NineLevelSolver.solve(
        definition: definition,
        initialMarkers: [
            BoardCoordinate(row: 0, column: 0),
            BoardCoordinate(row: 0, column: 1)
        ]
    )

    #expect(result.multiplicity == .none)
    #expect(result.firstSolution == nil)
}

@Test func bundledDay3CatalogIsValidUniqueAndDeterministic() throws {
    let pack = try NineLevelCatalog.loadBundled()
    let firstPass = try NineLevelPackValidator.validate(pack)
    let secondPass = try NineLevelPackValidator.validate(pack)

    #expect(pack.schemaVersion == 1)
    #expect(pack.levels.count == 20)
    #expect(NineContentGate.day3.isSatisfied(by: pack.levels.count))
    #expect(!NineContentGate.testFlight.isSatisfied(by: pack.levels.count))

    #expect(Array(pack.levels.prefix(5)).allSatisfy { $0.kind == .onboarding })
    #expect(Array(pack.levels.dropFirst(5)).allSatisfy { $0.kind == .standard })

    #expect(firstPass.count == pack.levels.count)
    #expect(firstPass.allSatisfy { $0.solver.multiplicity == .unique })

    let firstSolutions = firstPass.map { $0.solver.firstSolution }
    let secondSolutions = secondPass.map { $0.solver.firstSolution }
    let firstMetrics = firstPass.map { $0.solver.metrics }
    let secondMetrics = secondPass.map { $0.solver.metrics }

    #expect(firstSolutions == secondSolutions)
    #expect(firstMetrics == secondMetrics)
}

@Test func bundledSolutionsMatchAuthoredSolutions() throws {
    let validated = try NineLevelCatalog.validatedBundled()

    for item in validated {
        #expect(Set(item.solver.firstSolution ?? []) == Set(item.record.solution))
        #expect(item.record.initialMarkers.allSatisfy {
            Set(item.record.solution).contains($0)
        })
        #expect((1...5).contains(item.record.difficulty))
        #expect(item.solver.metrics.maxBranching > 0 || item.level.initialMarkers.count == item.level.definition.size)
    }
}

@Test func validatorRejectsDuplicateLevelIDs() throws {
    let pack = try NineLevelCatalog.loadBundled()
    let duplicate = NineLevelPack(
        schemaVersion: pack.schemaVersion,
        levels: [pack.levels[0], pack.levels[0]]
    )

    #expect(throws: NineLevelPackError.duplicateLevelID(pack.levels[0].id)) {
        _ = try NineLevelPackValidator.validate(duplicate)
    }
}

@Test func validatorRejectsUnsupportedPackVersion() throws {
    let pack = try NineLevelCatalog.loadBundled()
    let unsupported = NineLevelPack(
        schemaVersion: 999,
        levels: pack.levels
    )

    #expect(throws: NineLevelPackError.unsupportedSchemaVersion(999)) {
        _ = try NineLevelPackValidator.validate(unsupported)
    }
}
