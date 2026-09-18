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
