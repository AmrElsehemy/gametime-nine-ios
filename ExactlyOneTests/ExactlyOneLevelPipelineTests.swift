import Foundation
import Testing
@testable import ExactlyOne

@Test func solverDistinguishesMultipleSolutionsAndStopsAtTwo() throws {
    let definition = try LevelDefinition(
        id: "ambiguous",
        size: 6,
        regionIDs: (0..<6).flatMap { row in
            Array(repeating: row, count: 6)
        },
        adjacencyRule: .none
    )

    let result = ExactlyOneLevelSolver.solve(definition: definition)

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

    let result = ExactlyOneLevelSolver.solve(
        definition: definition,
        initialMarkers: [
            BoardCoordinate(row: 0, column: 0),
            BoardCoordinate(row: 0, column: 1)
        ]
    )

    #expect(result.multiplicity == .none)
    #expect(result.firstSolution == nil)
}

@Test func bundledV1CatalogIsValidUniqueAndDeterministic() throws {
    let pack = try ExactlyOneLevelCatalog.loadBundled()
    let firstPass = try ExactlyOneLevelPackValidator.validate(pack)
    let secondPass = try ExactlyOneLevelPackValidator.validate(pack)

    #expect(pack.schemaVersion == 1)
    #expect(pack.levels.count == 160)
    #expect(ExactlyOneContentGate.day3.isSatisfied(by: pack.levels.count))
    #expect(ExactlyOneContentGate.testFlight.isSatisfied(by: pack.levels.count))
    #expect(ExactlyOneContentGate.submission.isSatisfied(by: pack.levels.count))
    #expect(ExactlyOneContentGate.v1Target.isSatisfied(by: pack.levels.count))

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
    let validated = try ExactlyOneLevelCatalog.validatedBundled()

    for item in validated {
        #expect(Set(item.solver.firstSolution ?? []) == Set(item.record.solution))
        #expect(item.record.initialMarkers.allSatisfy {
            Set(item.record.solution).contains($0)
        })
        #expect((1...5).contains(item.record.difficulty))
        #expect(item.solver.metrics.maxBranching > 0 || item.level.initialMarkers.count == item.level.definition.size)
    }
}

@Test func bundledChapterTwoIsHarderAndFollowsChapterOne() throws {
    let pack = try ExactlyOneLevelCatalog.loadBundled()
    let chapters = pack.resolvedChapters
    let levels = PrototypeLevels.production

    #expect(chapters.map(\.number) == [1, 2])
    #expect(chapters[0].requiredStars == 0)
    #expect(chapters[1].requiredStars == 180)

    // The original 100 levels keep their ids and stay in Chapter 1.
    #expect(levels.prefix(100).allSatisfy { $0.chapter == 1 && $0.definition.id.hasPrefix("v1-") })
    let chapterTwo = Array(levels.dropFirst(100))
    #expect(chapterTwo.count == 60)
    #expect(chapterTwo.allSatisfy { $0.chapter == 2 && $0.definition.id.hasPrefix("v2-") })
    #expect(chapterTwo.allSatisfy { $0.definition.size >= 8 && $0.initialMarkers.count <= 1 })
}

@Test func validatorRejectsUnreachableOrOutOfSequenceChapters() throws {
    let pack = try ExactlyOneLevelCatalog.loadBundled()
    let chapterOne = Array(pack.levels.prefix(2))
    var chapterTwo = pack.levels[100]
    chapterTwo.chapter = 2

    let unreachable = ExactlyOneLevelPack(
        schemaVersion: 1,
        chapters: [
            ExactlyOneChapter(number: 1, title: "One", requiredStars: 0),
            ExactlyOneChapter(number: 2, title: "Two", requiredStars: 7)
        ],
        levels: chapterOne + [chapterTwo]
    )
    #expect(throws: ExactlyOneLevelPackError.self) {
        _ = try ExactlyOneLevelPackValidator.validate(unreachable)
    }

    var skipped = chapterTwo
    skipped.chapter = 3
    let outOfSequence = ExactlyOneLevelPack(
        schemaVersion: 1,
        chapters: unreachable.chapters,
        levels: chapterOne + [skipped]
    )
    #expect(throws: ExactlyOneLevelPackError.invalidChapter(levelID: skipped.id, chapter: 3)) {
        _ = try ExactlyOneLevelPackValidator.validate(outOfSequence)
    }

    let lockedFirstChapter = ExactlyOneLevelPack(
        schemaVersion: 1,
        chapters: [ExactlyOneChapter(number: 1, title: "One", requiredStars: 3)],
        levels: chapterOne
    )
    #expect(throws: ExactlyOneLevelPackError.malformedChapters("chapter 1 must be open")) {
        _ = try ExactlyOneLevelPackValidator.validate(lockedFirstChapter)
    }
}

@Test func chapterTwoOpensOnChapterOneStarsAndStaysOpen() throws {
    let levels = PrototypeLevels.production
    let chapters = PrototypeLevels.productionChapters
    let chapterTwo = try #require(chapters.first { $0.number == 2 })
    let firstOfChapterTwo = try #require(levels.first { $0.chapter == 2 }).definition.id
    var state = ExactlyOneSaveState.fresh(levels: levels)

    #expect(
        ExactlyOneChapterGate.status(of: chapterTwo, levels: levels, progress: state)
            == .locked(earnedStars: 0, requiredStars: 180)
    )
    let openedWithNoStars = state.unlockEarnedChapters(levels: levels, chapters: chapters)
    #expect(openedWithNoStars.isEmpty)

    func rate(_ level: PrototypeLevel, stars: Int) {
        var progress = ExactlyOneLevelProgress(completionCount: 1)
        progress.mastery = ExactlyOnePersonalMastery(stars: stars, best: nil)
        state.levelProgress[level.definition.id] = progress
    }

    // Two stars on 89 levels is 178: two short.
    for level in levels.prefix(89) { rate(level, stars: 2) }
    // Stars earned inside Chapter 2 don't count toward its own gate.
    rate(try #require(levels.first { $0.chapter == 2 }), stars: 3)
    #expect(
        ExactlyOneChapterGate.status(of: chapterTwo, levels: levels, progress: state)
            == .locked(earnedStars: 178, requiredStars: 180)
    )
    let openedShort = state.unlockEarnedChapters(levels: levels, chapters: chapters)
    #expect(openedShort.isEmpty)
    #expect(!state.unlockedLevelIDs.contains(firstOfChapterTwo))

    // Replaying an old puzzle for a third star tips it over.
    rate(levels[0], stars: 3)
    rate(levels[1], stars: 3)
    #expect(ExactlyOneChapterGate.status(of: chapterTwo, levels: levels, progress: state) == .open)
    let opened = state.unlockEarnedChapters(levels: levels, chapters: chapters)
    #expect(opened == [chapterTwo])
    #expect(state.unlockedLevelIDs.contains(firstOfChapterTwo))
    let openedAgain = state.unlockEarnedChapters(levels: levels, chapters: chapters)
    #expect(openedAgain.isEmpty)

    // An opened chapter survives a save round trip and a sanitize pass.
    let reloaded = try ExactlyOneSaveCodec.decode(ExactlyOneSaveCodec.encode(state))
        .sanitized(levels: levels, todayDayKey: "2026-10-30")
    #expect(reloaded.unlockedLevelIDs.contains(firstOfChapterTwo))
}

@Test func dailyPoolIgnoresChapterTwoSoExistingDaysKeepTheirPuzzle() throws {
    let levels = PrototypeLevels.production
    let pool = ExactlyOneDailyChallenge.pool(from: levels)

    #expect(pool.count == 100)
    #expect(pool.allSatisfy { $0.chapter == 1 })

    // Pinned to the selections 1.0.1 made from its 100-level catalog.
    let pinned: [(TimeInterval, Int)] = [
        (1_793_318_400, 36), // 2026-10-30
        (1_798_761_600, 97)  // 2027-01-01
    ]
    for (seconds, expected) in pinned {
        let index = ExactlyOneDailyChallenge.levelIndex(
            for: Date(timeIntervalSince1970: seconds),
            in: pool,
            excludingFirst: 5
        )
        #expect(index == expected)
    }
}

@Test func validatorRejectsDuplicateLevelIDs() throws {
    let pack = try ExactlyOneLevelCatalog.loadBundled()
    let duplicate = ExactlyOneLevelPack(
        schemaVersion: pack.schemaVersion,
        levels: [pack.levels[0], pack.levels[0]]
    )

    #expect(throws: ExactlyOneLevelPackError.duplicateLevelID(pack.levels[0].id)) {
        _ = try ExactlyOneLevelPackValidator.validate(duplicate)
    }
}

@Test func validatorRejectsUnsupportedPackVersion() throws {
    let pack = try ExactlyOneLevelCatalog.loadBundled()
    let unsupported = ExactlyOneLevelPack(
        schemaVersion: 999,
        levels: pack.levels
    )

    #expect(throws: ExactlyOneLevelPackError.unsupportedSchemaVersion(999)) {
        _ = try ExactlyOneLevelPackValidator.validate(unsupported)
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

    let migrated = try ExactlyOneSaveCodec.decode(Data(legacy.utf8))

    #expect(migrated.schemaVersion == ExactlyOneSaveState.currentSchemaVersion)
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

    let migrated = try ExactlyOneSaveCodec.decode(Data(legacy.utf8))

    #expect(migrated.schemaVersion == ExactlyOneSaveState.currentSchemaVersion)
    #expect(migrated.progressionSession == nil)
    #expect(migrated.dailySession?.levelID == "v1-006")
    #expect(migrated.dailySession?.dayKey == "2026-09-18")
    #expect(migrated.dailySession?.markers == [BoardCoordinate(row: 0, column: 1)])
    #expect(migrated.lastPlayMode == .daily)
}

@Test func saveCodecRoundTripsProgressAndBestTime() throws {
    let levels = PrototypeLevels.production
    var state = ExactlyOneSaveState.fresh(levels: levels)
    let level = try #require(levels.first)

    state.recordProgressionCompletion(
        levelID: level.definition.id,
        nextLevelID: levels.dropFirst().first?.definition.id,
        durationSeconds: 12.5,
        dayKey: "2026-09-18"
    )

    let encoded = try ExactlyOneSaveCodec.encode(state)
    let decoded = try ExactlyOneSaveCodec.decode(encoded)

    #expect(decoded == state)
    #expect(decoded.levelProgress[level.definition.id]?.bestDurationSeconds == 12.5)
}

@Test func saveCodecRoundTripsIndependentProgressionAndDailySessions() throws {
    let levels = PrototypeLevels.production
    var state = ExactlyOneSaveState.fresh(levels: levels)
    let progression = levels[0]
    let daily = levels[5]

    state.setSession(
        ExactlyOneSavedSession(
            mode: .progression,
            levelID: progression.definition.id,
            dayKey: nil,
            markers: progression.initialMarkers.sorted()
        )
    )
    state.setSession(
        ExactlyOneSavedSession(
            mode: .daily,
            levelID: daily.definition.id,
            dayKey: "2026-09-18",
            markers: daily.initialMarkers.sorted()
        )
    )

    let decoded = try ExactlyOneSaveCodec.decode(ExactlyOneSaveCodec.encode(state))

    #expect(decoded.progressionSession == state.progressionSession)
    #expect(decoded.dailySession == state.dailySession)
    #expect(decoded.lastPlayMode == .daily)
}

@Test func dailyChallengeSelectionIsStableAndSupportsBundledOverride() throws {
    let levels = PrototypeLevels.production
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    let first = ExactlyOneDailyChallenge.levelIndex(
        for: date,
        in: levels,
        excludingFirst: 5
    )
    let second = ExactlyOneDailyChallenge.levelIndex(
        for: date,
        in: levels,
        excludingFirst: 5
    )

    #expect(first == second)
    let selected = try #require(first)
    #expect(selected >= 5)
    #expect(selected < levels.count)

    let overrideIndex = try #require(levels.indices.dropFirst(5).first)
    let overridden = ExactlyOneDailyChallenge.levelIndex(
        for: date,
        in: levels,
        excludingFirst: 5,
        overrideLevelID: levels[overrideIndex].definition.id
    )
    #expect(overridden == overrideIndex)
}

@Test func utcDayKeysDoNotDependOnDeviceTimezone() {
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    let key = ExactlyOneUTCDate.dayKey(for: instant)

    #expect(key.count == 10)
    #expect(ExactlyOneUTCDate.dayDistance(from: key, to: key) == 0)
}

@Test func streakAllowsOneMissWithoutInflatingTheCount() {
    var streak = ExactlyOneStreakState.empty

    streak = ExactlyOneStreakPolicy.applyingCompletion(
        dayKey: "2026-09-01",
        to: streak
    )
    #expect(streak.currentCount == 1)

    streak = ExactlyOneStreakPolicy.applyingCompletion(
        dayKey: "2026-09-02",
        to: streak
    )
    #expect(streak.currentCount == 2)

    streak = ExactlyOneStreakPolicy.applyingCompletion(
        dayKey: "2026-09-04",
        to: streak
    )
    #expect(streak.currentCount == 2)

    streak = ExactlyOneStreakPolicy.applyingCompletion(
        dayKey: "2026-09-05",
        to: streak
    )
    #expect(streak.currentCount == 3)
    #expect(streak.longestCount == 3)

    streak = ExactlyOneStreakPolicy.applyingCompletion(
        dayKey: "2026-09-10",
        to: streak
    )
    #expect(streak.currentCount == 1)
    #expect(streak.longestCount == 3)
}

@Test func dailyCompletionIsIdempotentForStreakCredit() {
    let levels = PrototypeLevels.production
    let level = levels[5]
    var state = ExactlyOneSaveState.fresh(levels: levels)

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
    let suiteName = "ExactlyOneProgressStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let key = "corrupt-save"
    defaults.set(Data("definitely not json".utf8), forKey: key)

    let store = ExactlyOneProgressStore(defaults: defaults, key: key)
    let levels = PrototypeLevels.production
    let recovered = store.load(levels: levels)

    #expect(recovered.schemaVersion == ExactlyOneSaveState.currentSchemaVersion)
    #expect(recovered.currentLevelID == levels.first?.definition.id)
    #expect(recovered.unlockedLevelIDs == [levels[0].definition.id])
    #expect(defaults.data(forKey: key) == nil)
}

@Test func staleDailySessionIsDiscardedWithoutDestroyingProgressionSession() throws {
    let levels = PrototypeLevels.production
    var state = ExactlyOneSaveState.fresh(levels: levels)
    let progressionLevel = levels[0]
    let dailyLevel = levels[5]

    state.setSession(
        ExactlyOneSavedSession(
            mode: .progression,
            levelID: progressionLevel.definition.id,
            dayKey: nil,
            markers: progressionLevel.initialMarkers.sorted()
        )
    )
    state.setSession(
        ExactlyOneSavedSession(
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
    var state = ExactlyOneSaveState.fresh(levels: levels)
    let progressionLevel = levels[0]
    let dailyLevel = levels[5]

    let progressionSession = ExactlyOneSavedSession(
        mode: .progression,
        levelID: progressionLevel.definition.id,
        dayKey: nil,
        markers: progressionLevel.initialMarkers.sorted()
    )
    let dailySession = ExactlyOneSavedSession(
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
    var history = ExactlyOneMoveHistory()

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
    let state = ExactlyOneBoardState(
        level: level.definition,
        markers: level.initialMarkers
    )
    let before = state.markers

    let hint = try #require(
        ExactlyOneHintEngine.nextHint(level: level, state: state)
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

    var state = ExactlyOneBoardState(
        level: level.definition,
        markers: level.initialMarkers
    )
    let placed = state.placeMarker(at: wrong, level: level.definition)
    #expect(placed)

    let hint = try #require(
        ExactlyOneHintEngine.nextHint(level: level, state: state)
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

    var state = ExactlyOneBoardState(
        level: level.definition,
        markers: initial
    )
    let placedCorrect = state.placeMarker(at: correct, level: level.definition)
    let placedWrong = state.placeMarker(at: wrong, level: level.definition)
    #expect(placedCorrect)
    #expect(placedWrong)

    let evaluation = ExactlyOneConstraintEngine.evaluate(
        state,
        level: level.definition
    )
    #expect(evaluation.conflictingCoordinates.contains(correct))
    #expect(evaluation.conflictingCoordinates.contains(wrong))
    #expect(correct < wrong)

    let hint = try #require(
        ExactlyOneHintEngine.nextHint(level: level, state: state)
    )

    #expect(hint.action == .remove)
    #expect(hint.coordinate == wrong)
    #expect(hint.coordinate != correct)
}

@Test func restoredSessionPutsBackARemovedGiven() throws {
    let levels = PrototypeLevels.production
    let level = try #require(levels.first { !$0.initialMarkers.isEmpty })
    let removedGiven = try #require(level.initialMarkers.sorted().first)
    var state = ExactlyOneSaveState.fresh(levels: levels)
    state.setSession(
        ExactlyOneSavedSession(
            mode: .progression,
            levelID: level.definition.id,
            dayKey: nil,
            markers: level.initialMarkers.subtracting([removedGiven]).sorted()
        )
    )

    let sanitized = state.sanitized(levels: levels, todayDayKey: "2026-09-18")

    #expect(sanitized.progressionSession?.markers == level.initialMarkers.sorted())
}
