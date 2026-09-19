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

// MARK: - Persistence and progression

enum NinePlayMode: String, Codable, Equatable, Sendable {
    case progression
    case daily
}

struct NineLevelProgress: Codable, Equatable, Sendable {
    var completionCount: Int
    var bestDurationSeconds: Double?
    var lastCompletedDayKey: String?

    init(
        completionCount: Int = 0,
        bestDurationSeconds: Double? = nil,
        lastCompletedDayKey: String? = nil
    ) {
        self.completionCount = completionCount
        self.bestDurationSeconds = bestDurationSeconds
        self.lastCompletedDayKey = lastCompletedDayKey
    }

    mutating func recordCompletion(
        durationSeconds: Double?,
        dayKey: String
    ) {
        completionCount += 1
        lastCompletedDayKey = dayKey

        guard let durationSeconds,
              durationSeconds.isFinite,
              durationSeconds >= 0 else {
            return
        }

        if let currentBest = bestDurationSeconds {
            bestDurationSeconds = min(currentBest, durationSeconds)
        } else {
            bestDurationSeconds = durationSeconds
        }
    }
}

struct NineStreakState: Codable, Equatable, Sendable {
    var currentCount: Int
    var longestCount: Int
    var lastCompletedDayKey: String?

    static let empty = NineStreakState(
        currentCount: 0,
        longestCount: 0,
        lastCompletedDayKey: nil
    )
}

struct NineSavedSession: Codable, Equatable, Sendable {
    let mode: NinePlayMode
    let levelID: String
    let dayKey: String?
    var markers: [BoardCoordinate]
}

struct NineSaveState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var currentLevelID: String?
    var unlockedLevelIDs: [String]
    var levelProgress: [String: NineLevelProgress]
    var progressionSession: NineSavedSession?
    var dailySession: NineSavedSession?
    var lastPlayMode: NinePlayMode
    var dailyCompletions: [String: String]
    var streak: NineStreakState

    static func fresh(levels: [PrototypeLevel]) -> NineSaveState {
        let firstID = levels.first?.definition.id
        return NineSaveState(
            schemaVersion: currentSchemaVersion,
            currentLevelID: firstID,
            unlockedLevelIDs: firstID.map { [$0] } ?? [],
            levelProgress: [:],
            progressionSession: nil,
            dailySession: nil,
            lastPlayMode: .progression,
            dailyCompletions: [:],
            streak: .empty
        )
    }

    func session(for mode: NinePlayMode) -> NineSavedSession? {
        switch mode {
        case .progression:
            return progressionSession
        case .daily:
            return dailySession
        }
    }

    mutating func setSession(_ session: NineSavedSession) {
        lastPlayMode = session.mode
        switch session.mode {
        case .progression:
            progressionSession = session
        case .daily:
            dailySession = session
        }
    }

    mutating func clearSession(for mode: NinePlayMode) {
        switch mode {
        case .progression:
            progressionSession = nil
        case .daily:
            dailySession = nil
        }
    }

    mutating func recordProgressionCompletion(
        levelID: String,
        nextLevelID: String?,
        durationSeconds: Double?,
        dayKey: String
    ) {
        recordLevelCompletion(
            levelID: levelID,
            durationSeconds: durationSeconds,
            dayKey: dayKey
        )

        if let nextLevelID {
            if !unlockedLevelIDs.contains(nextLevelID) {
                unlockedLevelIDs.append(nextLevelID)
            }
            currentLevelID = nextLevelID
        } else {
            currentLevelID = levelID
        }

        progressionSession = nil
    }

    mutating func recordDailyCompletion(
        levelID: String,
        durationSeconds: Double?,
        dayKey: String
    ) {
        recordLevelCompletion(
            levelID: levelID,
            durationSeconds: durationSeconds,
            dayKey: dayKey
        )

        if dailyCompletions[dayKey] == nil {
            dailyCompletions[dayKey] = levelID
            streak = NineStreakPolicy.applyingCompletion(
                dayKey: dayKey,
                to: streak
            )
        }

        dailySession = nil
    }

    private mutating func recordLevelCompletion(
        levelID: String,
        durationSeconds: Double?,
        dayKey: String
    ) {
        var progress = levelProgress[levelID] ?? NineLevelProgress()
        progress.recordCompletion(
            durationSeconds: durationSeconds,
            dayKey: dayKey
        )
        levelProgress[levelID] = progress
    }

    func sanitized(levels: [PrototypeLevel], todayDayKey: String) -> NineSaveState {
        let catalogIDs = levels.map(\.definition.id)
        let validIDs = Set(catalogIDs)
        let firstID = catalogIDs.first

        var cleaned = self
        cleaned.schemaVersion = Self.currentSchemaVersion
        cleaned.unlockedLevelIDs = catalogIDs.filter {
            unlockedLevelIDs.contains($0)
        }

        if let firstID, !cleaned.unlockedLevelIDs.contains(firstID) {
            cleaned.unlockedLevelIDs.insert(firstID, at: 0)
        }

        if let currentLevelID,
           validIDs.contains(currentLevelID) {
            cleaned.currentLevelID = currentLevelID
            if !cleaned.unlockedLevelIDs.contains(currentLevelID) {
                cleaned.unlockedLevelIDs.append(currentLevelID)
            }
        } else {
            cleaned.currentLevelID = firstID
        }

        cleaned.levelProgress = levelProgress.filter {
            validIDs.contains($0.key)
        }
        cleaned.dailyCompletions = dailyCompletions.filter {
            validIDs.contains($0.value)
        }

        cleaned.progressionSession = sanitizedSession(
            progressionSession,
            expectedMode: .progression,
            levels: levels,
            todayDayKey: todayDayKey
        )
        cleaned.dailySession = sanitizedSession(
            dailySession,
            expectedMode: .daily,
            levels: levels,
            todayDayKey: todayDayKey
        )

        if cleaned.lastPlayMode == .daily && cleaned.dailySession == nil {
            cleaned.lastPlayMode = .progression
        }

        return cleaned
    }

    private func sanitizedSession(
        _ session: NineSavedSession?,
        expectedMode: NinePlayMode,
        levels: [PrototypeLevel],
        todayDayKey: String
    ) -> NineSavedSession? {
        guard let session,
              session.mode == expectedMode,
              let level = levels.first(where: {
                  $0.definition.id == session.levelID
              }) else {
            return nil
        }

        if expectedMode == .daily && session.dayKey != todayDayKey {
            return nil
        }

        let validMarkers = session.markers
            .filter(level.definition.contains)
            .sorted()

        return NineSavedSession(
            mode: expectedMode,
            levelID: session.levelID,
            dayKey: expectedMode == .daily ? session.dayKey : nil,
            markers: validMarkers
        )
    }
}

enum NineSaveError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case missingSchemaVersion
}

enum NineSaveCodec {
    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private struct LegacyV1: Codable {
        let schemaVersion: Int
        let currentLevelID: String?
        let unlockedLevelIDs: [String]
        let completedLevelIDs: [String]
    }

    private struct LegacyV2: Codable {
        let schemaVersion: Int
        let currentLevelID: String?
        let unlockedLevelIDs: [String]
        let levelProgress: [String: NineLevelProgress]
        let activeSession: NineSavedSession?
        let dailyCompletions: [String: String]
        let streak: NineStreakState
    }

    static func encode(_ state: NineSaveState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    static func decode(_ data: Data) throws -> NineSaveState {
        let decoder = JSONDecoder()
        let probe: SchemaProbe
        do {
            probe = try decoder.decode(SchemaProbe.self, from: data)
        } catch {
            throw NineSaveError.missingSchemaVersion
        }

        switch probe.schemaVersion {
        case NineSaveState.currentSchemaVersion:
            return try decoder.decode(NineSaveState.self, from: data)
        case 2:
            let legacy = try decoder.decode(LegacyV2.self, from: data)
            return NineSaveState(
                schemaVersion: NineSaveState.currentSchemaVersion,
                currentLevelID: legacy.currentLevelID,
                unlockedLevelIDs: legacy.unlockedLevelIDs,
                levelProgress: legacy.levelProgress,
                progressionSession: legacy.activeSession?.mode == .progression
                    ? legacy.activeSession
                    : nil,
                dailySession: legacy.activeSession?.mode == .daily
                    ? legacy.activeSession
                    : nil,
                lastPlayMode: legacy.activeSession?.mode ?? .progression,
                dailyCompletions: legacy.dailyCompletions,
                streak: legacy.streak
            )
        case 1:
            let legacy = try decoder.decode(LegacyV1.self, from: data)
            var progress: [String: NineLevelProgress] = [:]
            for levelID in legacy.completedLevelIDs {
                progress[levelID] = NineLevelProgress(completionCount: 1)
            }
            return NineSaveState(
                schemaVersion: NineSaveState.currentSchemaVersion,
                currentLevelID: legacy.currentLevelID,
                unlockedLevelIDs: legacy.unlockedLevelIDs,
                levelProgress: progress,
                progressionSession: nil,
                dailySession: nil,
                lastPlayMode: .progression,
                dailyCompletions: [:],
                streak: .empty
            )
        default:
            throw NineSaveError.unsupportedSchemaVersion(probe.schemaVersion)
        }
    }
}

@MainActor
final class NineProgressStore {
    // Keep the existing storage key stable so v1/v2 installs migrate in place.
    private static let defaultKey = "nine.progress.save.v2"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = NineProgressStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load(
        levels: [PrototypeLevel],
        now: Date = Date()
    ) -> NineSaveState {
        guard let data = defaults.data(forKey: key) else {
            return NineSaveState.fresh(levels: levels)
        }

        do {
            let decoded = try NineSaveCodec.decode(data)
            let sanitized = decoded.sanitized(
                levels: levels,
                todayDayKey: NineUTCDate.dayKey(for: now)
            )
            if sanitized != decoded {
                save(sanitized)
            }
            return sanitized
        } catch {
            defaults.removeObject(forKey: key)
            return NineSaveState.fresh(levels: levels)
        }
    }

    func save(_ state: NineSaveState) {
        guard let data = try? NineSaveCodec.encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    @discardableResult
    func reset(levels: [PrototypeLevel]) -> NineSaveState {
        defaults.removeObject(forKey: key)
        return NineSaveState.fresh(levels: levels)
    }
}

// MARK: - Daily challenge and streak

enum NineUTCDate {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func dayDistance(from startKey: String, to endKey: String) -> Int? {
        guard let start = date(from: startKey),
              let end = date(from: endKey) else {
            return nil
        }
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    private static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(
            from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: year,
                month: month,
                day: day
            )
        )
    }
}

enum NineDailyChallenge {
    static func levelIndex(
        for date: Date,
        in levels: [PrototypeLevel],
        excludingFirst onboardingCount: Int,
        overrideLevelID: String? = nil
    ) -> Int? {
        guard !levels.isEmpty else { return nil }

        let start = min(max(0, onboardingCount), levels.count)
        let candidateIndices = Array(levels.indices.dropFirst(start))
        guard !candidateIndices.isEmpty else { return levels.indices.first }

        if let overrideLevelID,
           let index = candidateIndices.first(where: {
               levels[$0].definition.id == overrideLevelID
           }) {
            return index
        }

        let key = "nine-daily-v1|\(NineUTCDate.dayKey(for: date))"
        let hash = stableHash(key)
        return candidateIndices[Int(hash % UInt64(candidateIndices.count))]
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

enum NineStreakPolicy {
    /// A same-day repeat is ignored. Consecutive UTC days increment the streak.
    /// One missed UTC day preserves (but does not increment) the current streak.
    /// Larger gaps reset to one. Using UTC makes timezone changes non-destructive.
    static func applyingCompletion(
        dayKey: String,
        to streak: NineStreakState
    ) -> NineStreakState {
        guard let previous = streak.lastCompletedDayKey else {
            return NineStreakState(
                currentCount: 1,
                longestCount: max(1, streak.longestCount),
                lastCompletedDayKey: dayKey
            )
        }

        guard let gap = NineUTCDate.dayDistance(from: previous, to: dayKey) else {
            return streak
        }

        if gap <= 0 {
            return streak
        }

        let nextCount: Int
        switch gap {
        case 1:
            nextCount = max(1, streak.currentCount) + 1
        case 2:
            nextCount = max(1, streak.currentCount)
        default:
            nextCount = 1
        }

        return NineStreakState(
            currentCount: nextCount,
            longestCount: max(streak.longestCount, nextCount),
            lastCompletedDayKey: dayKey
        )
    }
}
