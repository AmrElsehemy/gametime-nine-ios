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

@Test func saveCodecMigratesSyntheticV1State() throws {
    let legacy = """
    {
      "schemaVersion": 1,
      "currentLevelID": "v1-003",
      "unlockedLevelIDs": ["v1-001", "v1-002", "v1-003"],
      "completedLevelIDs": ["v1-001", "v1-002"]
    }
    """

    let migrated = try NineSaveCodec.decode(Data(legacy.utf8))

    #expect(migrated.schemaVersion == NineSaveState.currentSchemaVersion)
    #expect(migrated.currentLevelID == "v1-003")
    #expect(migrated.unlockedLevelIDs == ["v1-001", "v1-002", "v1-003"])
    #expect(migrated.levelProgress["v1-001"]?.completionCount == 1)
    #expect(migrated.levelProgress["v1-002"]?.completionCount == 1)
    #expect(migrated.progressionSession == nil)
    #expect(migrated.dailySession == nil)
    #expect(migrated.lastPlayMode == .progression)
    #expect(migrated.streak == .empty)
}

@Test func saveCodecMigratesV2ActiveSessionIntoItsModeSlot() throws {
    let legacy = """
    {
      "schemaVersion": 2,
      "currentLevelID": "v1-003",
      "unlockedLevelIDs": ["v1-001", "v1-002", "v1-003"],
      "levelProgress": {},
      "activeSession": {
        "mode": "daily",
        "levelID": "v1-006",
        "dayKey": "2026-09-18",
        "markers": [{"row": 0, "column": 1}]
      },
      "dailyCompletions": {},
      "streak": {
        "currentCount": 0,
        "longestCount": 0,
        "lastCompletedDayKey": null
      }
    }
    """

    let migrated = try NineSaveCodec.decode(Data(legacy.utf8))

    #expect(migrated.schemaVersion == NineSaveState.currentSchemaVersion)
    #expect(migrated.progressionSession == nil)
    #expect(migrated.dailySession?.levelID == "v1-006")
    #expect(migrated.dailySession?.dayKey == "2026-09-18")
    #expect(migrated.dailySession?.markers == [BoardCoordinate(row: 0, column: 1)])
    #expect(migrated.lastPlayMode == .daily)
}

@Test func saveCodecRoundTripsProgressAndBestTime() throws {
    let levels = PrototypeLevels.production
    var state = NineSaveState.fresh(levels: levels)
    let level = try #require(levels.first)

    state.recordProgressionCompletion(
        levelID: level.definition.id,
        nextLevelID: levels.dropFirst().first?.definition.id,
        durationSeconds: 12.5,
        dayKey: "2026-09-18"
    )

    let encoded = try NineSaveCodec.encode(state)
    let decoded = try NineSaveCodec.decode(encoded)

    #expect(decoded == state)
    #expect(decoded.levelProgress[level.definition.id]?.bestDurationSeconds == 12.5)
}

@Test func saveCodecRoundTripsIndependentProgressionAndDailySessions() throws {
    let levels = PrototypeLevels.production
    var state = NineSaveState.fresh(levels: levels)
    let progression = levels[0]
    let daily = levels[5]

    state.setSession(
        NineSavedSession(
            mode: .progression,
            levelID: progression.definition.id,
            dayKey: nil,
            markers: progression.initialMarkers.sorted()
        )
    )
    state.setSession(
        NineSavedSession(
            mode: .daily,
            levelID: daily.definition.id,
            dayKey: "2026-09-18",
            markers: daily.initialMarkers.sorted()
        )
    )

    let decoded = try NineSaveCodec.decode(NineSaveCodec.encode(state))

    #expect(decoded.progressionSession == state.progressionSession)
    #expect(decoded.dailySession == state.dailySession)
    #expect(decoded.lastPlayMode == .daily)
}

@Test func dailyChallengeSelectionIsStableAndSupportsBundledOverride() throws {
    let levels = PrototypeLevels.production
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    let first = NineDailyChallenge.levelIndex(
        for: date,
        in: levels,
        excludingFirst: 5
    )
    let second = NineDailyChallenge.levelIndex(
        for: date,
        in: levels,
        excludingFirst: 5
    )

    #expect(first == second)
    let selected = try #require(first)
    #expect(selected >= 5)
    #expect(selected < levels.count)

    let overrideIndex = try #require(levels.indices.dropFirst(5).first)
    let overridden = NineDailyChallenge.levelIndex(
        for: date,
        in: levels,
        excludingFirst: 5,
        overrideLevelID: levels[overrideIndex].definition.id
    )
    #expect(overridden == overrideIndex)
}

@Test func utcDayKeysDoNotDependOnDeviceTimezone() {
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    let key = NineUTCDate.dayKey(for: instant)

    #expect(key.count == 10)
    #expect(NineUTCDate.dayDistance(from: key, to: key) == 0)
}

@Test func streakAllowsOneMissWithoutInflatingTheCount() {
    var streak = NineStreakState.empty

    streak = NineStreakPolicy.applyingCompletion(
        dayKey: "2026-09-01",
        to: streak
    )
    #expect(streak.currentCount == 1)

    streak = NineStreakPolicy.applyingCompletion(
        dayKey: "2026-09-02",
        to: streak
    )
    #expect(streak.currentCount == 2)

    streak = NineStreakPolicy.applyingCompletion(
        dayKey: "2026-09-04",
        to: streak
    )
    #expect(streak.currentCount == 2)

    streak = NineStreakPolicy.applyingCompletion(
        dayKey: "2026-09-05",
        to: streak
    )
    #expect(streak.currentCount == 3)
    #expect(streak.longestCount == 3)

    streak = NineStreakPolicy.applyingCompletion(
        dayKey: "2026-09-10",
        to: streak
    )
    #expect(streak.currentCount == 1)
    #expect(streak.longestCount == 3)
}

@Test func dailyCompletionIsIdempotentForStreakCredit() {
    let levels = PrototypeLevels.production
    let level = levels[5]
    var state = NineSaveState.fresh(levels: levels)

    state.recordDailyCompletion(
        levelID: level.definition.id,
        durationSeconds: 20,
        dayKey: "2026-09-18"
    )
    state.recordDailyCompletion(
        levelID: level.definition.id,
        durationSeconds: 18,
        dayKey: "2026-09-18"
    )

    #expect(state.streak.currentCount == 1)
    #expect(state.dailyCompletions.count == 1)
    #expect(state.levelProgress[level.definition.id]?.completionCount == 2)
    #expect(state.levelProgress[level.definition.id]?.bestDurationSeconds == 18)
}

@Test @MainActor func corruptedSaveRecoversToFreshOfflineProgress() throws {
    let suiteName = "NineProgressStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let key = "corrupt-save"
    defaults.set(Data("definitely not json".utf8), forKey: key)

    let store = NineProgressStore(defaults: defaults, key: key)
    let levels = PrototypeLevels.production
    let recovered = store.load(levels: levels)

    #expect(recovered.schemaVersion == NineSaveState.currentSchemaVersion)
    #expect(recovered.currentLevelID == levels.first?.definition.id)
    #expect(recovered.unlockedLevelIDs == [levels[0].definition.id])
    #expect(defaults.data(forKey: key) == nil)
}

@Test func staleDailySessionIsDiscardedWithoutDestroyingProgressionSession() throws {
    let levels = PrototypeLevels.production
    var state = NineSaveState.fresh(levels: levels)
    let progressionLevel = levels[0]
    let dailyLevel = levels[5]

    state.setSession(
        NineSavedSession(
            mode: .progression,
            levelID: progressionLevel.definition.id,
            dayKey: nil,
            markers: progressionLevel.initialMarkers.sorted()
        )
    )
    state.setSession(
        NineSavedSession(
            mode: .daily,
            levelID: dailyLevel.definition.id,
            dayKey: "2026-09-17",
            markers: [BoardCoordinate(row: 0, column: 0)]
        )
    )

    let sanitized = state.sanitized(
        levels: levels,
        todayDayKey: "2026-09-18"
    )

    #expect(sanitized.dailySession == nil)
    #expect(sanitized.progressionSession?.levelID == progressionLevel.definition.id)
    #expect(sanitized.lastPlayMode == .progression)
    #expect(sanitized.currentLevelID == progressionLevel.definition.id)
}

@Test func completingOneModeDoesNotDiscardTheOtherModesSession() throws {
    let levels = PrototypeLevels.production
    var state = NineSaveState.fresh(levels: levels)
    let progressionLevel = levels[0]
    let dailyLevel = levels[5]

    let progressionSession = NineSavedSession(
        mode: .progression,
        levelID: progressionLevel.definition.id,
        dayKey: nil,
        markers: progressionLevel.initialMarkers.sorted()
    )
    let dailySession = NineSavedSession(
        mode: .daily,
        levelID: dailyLevel.definition.id,
        dayKey: "2026-09-18",
        markers: dailyLevel.initialMarkers.sorted()
    )

    state.setSession(progressionSession)
    state.setSession(dailySession)
    state.recordDailyCompletion(
        levelID: dailyLevel.definition.id,
        durationSeconds: 20,
        dayKey: "2026-09-18"
    )

    #expect(state.dailySession == nil)
    #expect(state.progressionSession == progressionSession)

    state.setSession(dailySession)
    state.recordProgressionCompletion(
        levelID: progressionLevel.definition.id,
        nextLevelID: levels[1].definition.id,
        durationSeconds: 15,
        dayKey: "2026-09-18"
    )

    #expect(state.progressionSession == nil)
    #expect(state.dailySession == dailySession)
}

@Test func moveHistoryUndoIsPredictableAndStopsAtInitialState() throws {
    let level = PrototypeLevels.production[5]
    let initial = level.initialMarkers
    let missing = level.solution.filter { !initial.contains($0) }
    #expect(missing.count >= 2)
    let firstCoordinate = try #require(missing.first)
    let secondCoordinate = try #require(missing.dropFirst().first)

    let firstMove = initial.union([firstCoordinate])
    let secondMove = firstMove.union([secondCoordinate])
    var history = NineMoveHistory()

    history.reset(to: initial)
    history.record(firstMove)
    history.record(secondMove)

    #expect(history.canUndo)
    #expect(history.undo() == firstMove)
    #expect(history.undo() == initial)
    #expect(!history.canUndo)
    #expect(history.undo() == nil)
}

@Test func hintPreviewPlacesAUniqueSolutionCellWithoutMutatingState() throws {
    let level = PrototypeLevels.production[5]
    let state = NineBoardState(
        level: level.definition,
        markers: level.initialMarkers
    )
    let before = state.markers

    let hint = try #require(
        NineHintEngine.nextHint(level: level, state: state)
    )

    #expect(hint.action == .place)
    #expect(Set(level.solution).contains(hint.coordinate))
    #expect(!state.markers.contains(hint.coordinate))
    #expect(state.markers == before)
}

@Test func hintRemovesWrongPlayerMarkerBeforeRevealingMore() throws {
    let level = PrototypeLevels.production[5]
    let solution = Set(level.solution)
    let wrong = try #require(
        (0..<level.definition.size).flatMap { row in
            (0..<level.definition.size).map {
                BoardCoordinate(row: row, column: $0)
            }
        }.first(where: {
            !solution.contains($0) && !level.initialMarkers.contains($0)
        })
    )

    var state = NineBoardState(
        level: level.definition,
        markers: level.initialMarkers
    )
    let placed = state.placeMarker(at: wrong, level: level.definition)
    #expect(placed)

    let hint = try #require(
        NineHintEngine.nextHint(level: level, state: state)
    )

    #expect(hint.action == .remove)
    #expect(hint.coordinate == wrong)
}

@Test func hintNeverRemovesCorrectMarkerWhenCorrectAndWrongMarkersConflict() throws {
    let level = PrototypeLevels.production[5]
    let solution = Set(level.solution)
    let initial = level.initialMarkers
    let correct = try #require(
        level.solution.first(where: {
            !initial.contains($0) && $0.column < level.definition.size - 1
        })
    )
    let wrong = try #require(
        ((correct.column + 1)..<level.definition.size)
            .map { BoardCoordinate(row: correct.row, column: $0) }
            .first(where: { !solution.contains($0) })
    )

    var state = NineBoardState(
        level: level.definition,
        markers: initial
    )
    #expect(state.placeMarker(at: correct, level: level.definition))
    #expect(state.placeMarker(at: wrong, level: level.definition))

    let evaluation = NineConstraintEngine.evaluate(
        state,
        level: level.definition
    )
    #expect(evaluation.conflictingCoordinates.contains(correct))
    #expect(evaluation.conflictingCoordinates.contains(wrong))
    #expect(correct < wrong)

    let hint = try #require(
        NineHintEngine.nextHint(level: level, state: state)
    )

    #expect(hint.action == .remove)
    #expect(hint.coordinate == wrong)
    #expect(hint.coordinate != correct)
}
