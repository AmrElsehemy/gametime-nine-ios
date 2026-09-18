import Foundation

extension PrototypeLevel {
    init(
        definition: LevelDefinition,
        initialMarkers: Set<BoardCoordinate>,
        solution: [BoardCoordinate]
    ) {
        self.definition = definition
        self.initialMarkers = initialMarkers
        self.solution = solution
    }
}

extension PrototypeLevels {
    /// Validated data-driven catalog. Gameplay can switch from the five hard-coded
    /// vertical-slice levels to this collection without changing puzzle rules.
    static let production: [PrototypeLevel] = {
        do {
            return try NineLevelCatalog.validatedBundled().map(\.level)
        } catch {
            preconditionFailure("Invalid bundled Nine level pack: \(error)")
        }
    }()
}
