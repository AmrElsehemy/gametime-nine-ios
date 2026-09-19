import Foundation
import UIKit
import Testing
@testable import Nine

@Test func semanticFeedbackCuesAreDistinctAndBounded() {
    let placement = NineFeedbackCue.cue(for: .placement)
    let invalid = NineFeedbackCue.cue(for: .invalid)
    let solved = NineFeedbackCue.cue(for: .solved)

    #expect(placement != invalid)
    #expect(invalid != solved)
    #expect(invalid.hapticIntensity > placement.hapticIntensity)
    #expect(solved.frequency > placement.frequency)

    for event in NineFeedbackEvent.allCases {
        let cue = NineFeedbackCue.cue(for: event)
        #expect((0...1).contains(cue.hapticIntensity))
        #expect((0...1).contains(cue.hapticSharpness))
        #expect(cue.frequency > 0)
        #expect(cue.duration > 0)
        #expect(cue.gain > 0)
    }
}

@MainActor
@Test func soundAndHapticsPreferencesPersistIndependently() {
    let suiteName = "NineFeedbackTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = NineFeedbackPreferenceStore(defaults: defaults)
    #expect(store.current == .defaults)

    store.setSoundEnabled(false)
    #expect(store.current.soundEnabled == false)
    #expect(store.current.hapticsEnabled == true)

    store.setHapticsEnabled(false)
    #expect(store.current.soundEnabled == false)
    #expect(store.current.hapticsEnabled == false)

    store.setSoundEnabled(true)
    #expect(store.current.soundEnabled == true)
    #expect(store.current.hapticsEnabled == false)
}

@Test func replayRoundTripReproducesFinalLogicalState() throws {
    let level = PrototypeLevels.production[5]
    let missing = level.solution.filter { !level.initialMarkers.contains($0) }
    let first = try #require(missing.first)
    let second = try #require(missing.dropFirst().first)

    var state = NineBoardState(
        level: level.definition,
        markers: level.initialMarkers
    )
    var history = NineMoveHistory()
    history.reset(to: state.markers)

    var recorder = NineReplayRecorder(
        level: level,
        mode: .progression,
        dayKey: nil,
        initialMarkers: state.markers,
        appVersion: "1.0",
        buildVersion: "42",
        replayID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    )

    let placedFirst = state.placeMarker(at: first, level: level.definition)
    #expect(placedFirst)
    history.record(state.markers)
    recorder.record(
        NineGameplayIntent(
            kind: .place,
            levelID: level.definition.id,
            coordinate: first
        )
    )

    let placedSecond = state.placeMarker(at: second, level: level.definition)
    #expect(placedSecond)
    history.record(state.markers)
    recorder.record(
        NineGameplayIntent(
            kind: .place,
            levelID: level.definition.id,
            coordinate: second
        )
    )

    let undoResult = history.undo()
    let undoMarkers = try #require(undoResult)
    state = NineBoardState(level: level.definition, markers: undoMarkers)
    recorder.record(
        NineGameplayIntent(
            kind: .undo,
            levelID: level.definition.id,
            coordinate: nil
        )
    )

    let replacedSecond = state.placeMarker(at: second, level: level.definition)
    #expect(replacedSecond)
    history.record(state.markers)
    recorder.record(
        NineGameplayIntent(
            kind: .place,
            levelID: level.definition.id,
            coordinate: second
        )
    )
    recorder.record(
        NineGameplayIntent(
            kind: .hintPreview,
            levelID: level.definition.id,
            coordinate: nil
        )
    )

    let encoded = try NineReplayCodec.encode(recorder.replay)
    let decoded = try NineReplayCodec.decode(encoded)
    let replayed = try NineReplayPlayer.finalState(replay: decoded, level: level)

    #expect(decoded == recorder.replay)
    #expect(replayed.markers == state.markers)
    #expect(decoded.schemaVersion == NineReplay.currentSchemaVersion)
    #expect(decoded.levelID == level.definition.id)
    #expect(decoded.levelSchemaVersion == level.definition.schemaVersion)
    #expect(decoded.appVersion == "1.0")
    #expect(decoded.buildVersion == "42")
    #expect(decoded.events.map(\.sequence) == Array(0..<decoded.events.count))
}

@Test func replayRejectsUnsupportedOrMalformedInputGracefully() throws {
    let level = PrototypeLevels.production[5]
    let replayID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!

    let incompatible = NineReplay(
        schemaVersion: 999,
        replayID: replayID,
        appVersion: "1.0",
        buildVersion: "42",
        levelID: level.definition.id,
        levelSchemaVersion: level.definition.schemaVersion,
        mode: NinePlayMode.progression.rawValue,
        dayKey: nil,
        initialMarkers: level.initialMarkers.sorted(),
        events: []
    )

    #expect(throws: NineReplayError.unsupportedSchemaVersion(999)) {
        _ = try NineReplayPlayer.finalState(replay: incompatible, level: level)
    }

    let malformed = NineReplay(
        schemaVersion: NineReplay.currentSchemaVersion,
        replayID: replayID,
        appVersion: "1.0",
        buildVersion: "42",
        levelID: level.definition.id,
        levelSchemaVersion: level.definition.schemaVersion,
        mode: NinePlayMode.progression.rawValue,
        dayKey: nil,
        initialMarkers: level.initialMarkers.sorted(),
        events: [
            NineReplayEvent(
                sequence: 7,
                kind: NineGameplayIntentKind.place.rawValue,
                coordinate: level.solution.first
            )
        ]
    )

    #expect(throws: NineReplayError.malformedEvent(sequence: 7)) {
        _ = try NineReplayPlayer.finalState(replay: malformed, level: level)
    }
}

@MainActor
@Test func diagnosticsAreBoundedAndSupportPayloadIsPrivacySafeByConstruction() throws {
    let buffer = NineDiagnosticsBuffer(capacity: 2)
    buffer.add("level", "loaded:v1-001", at: Date(timeIntervalSince1970: 1))
    buffer.add("save", "saved:v1-001", at: Date(timeIntervalSince1970: 2))
    buffer.add("level", "completed:v1-001", at: Date(timeIntervalSince1970: 3))

    #expect(buffer.breadcrumbs.count == 2)
    #expect(buffer.breadcrumbs.first?.message == "saved:v1-001")
    #expect(buffer.breadcrumbs.last?.message == "completed:v1-001")

    let package = NineSupportPackage(
        schemaVersion: NineSupportPackage.currentSchemaVersion,
        appVersion: "1.0",
        buildVersion: "42",
        deviceClass: "iPhone",
        osClass: "iOS 26",
        levelID: "v1-001",
        levelSchemaVersion: 1,
        replay: nil,
        breadcrumbs: buffer.breadcrumbs
    )

    let data = try JSONEncoder().encode(package)
    let decoded = try JSONDecoder().decode(NineSupportPackage.self, from: data)
    let json = String(decoding: data, as: UTF8.self)

    #expect(decoded == package)
    #expect(!json.contains("email"))
    #expect(!json.contains("playerName"))
    #expect(!json.contains("deviceName"))
    #expect(decoded.breadcrumbs.count == 2)
}

@Test func analyticsSchemaIncludesRequiredLaunchFunnelAndCommerceHooks() {
    let actual = Set(NineAnalyticsEventName.allCases.map(\.rawValue))
    let required: Set<String> = [
        "first_open",
        "session_start",
        "session_end",
        "tutorial_started",
        "tutorial_completed",
        "level_started",
        "level_completed",
        "level_abandoned",
        "invalid_move",
        "undo",
        "reset",
        "hint",
        "daily_started",
        "daily_completed",
        "reward_offer_shown",
        "reward_offer_accepted",
        "reward_completed",
        "iap_started",
        "iap_completed"
    ]

    #expect(required.isSubset(of: actual))
}

@MainActor
@Test func analyticsFirstOpenAndCriticalLifecycleEventsAreDeduplicated() {
    let suiteName = "NineAnalyticsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let client = CapturingAnalyticsClient()
    let lifecycle = NineAnalyticsLifecycleStore(defaults: defaults)
    let tracker = NineAnalyticsTracker(client: client, lifecycleStore: lifecycle)

    tracker.trackFirstOpenIfNeeded()
    tracker.trackFirstOpenIfNeeded()
    tracker.track(.sessionStart, dedupeKey: "session_start")
    tracker.track(.sessionStart, dedupeKey: "session_start")

    #expect(client.events.map(\.name) == [.firstOpen, .sessionStart])

    let secondClient = CapturingAnalyticsClient()
    let secondTracker = NineAnalyticsTracker(
        client: secondClient,
        lifecycleStore: NineAnalyticsLifecycleStore(defaults: defaults)
    )
    secondTracker.trackFirstOpenIfNeeded()
    #expect(secondClient.events.isEmpty)
}

@MainActor
@Test func analyticsAddsUsefulLevelDimensionsWithoutBoardCoordinates() {
    let client = CapturingAnalyticsClient()
    let tracker = NineAnalyticsTracker(client: client)
    let level = PrototypeLevels.production[5]

    tracker.track(
        .levelCompleted,
        level: level,
        mode: .progression,
        durationSeconds: 1.234,
        extra: ["reason": "solved"],
        dedupeKey: "attempt-1"
    )
    tracker.track(
        .levelCompleted,
        level: level,
        mode: .progression,
        durationSeconds: 9,
        dedupeKey: "attempt-1"
    )

    #expect(client.events.count == 1)
    let event = client.events[0]
    #expect(event.name == .levelCompleted)
    #expect(event.properties["level_id"] == level.definition.id)
    #expect(event.properties["level_version"] == String(level.definition.schemaVersion))
    #expect(event.properties["board_size"] == String(level.definition.size))
    #expect(event.properties["mode"] == NinePlayMode.progression.rawValue)
    #expect(event.properties["duration_ms"] == "1234")
    #expect(event.properties["reason"] == "solved")
    #expect(event.properties["row"] == nil)
    #expect(event.properties["column"] == nil)
}

@Test func gameCenterScoreConvertsToClampedMilliseconds() {
    #expect(NineGameCenterScore.milliseconds(durationSeconds: 1.234) == 1_234)
    #expect(NineGameCenterScore.milliseconds(durationSeconds: 0) == 1)
    #expect(NineGameCenterScore.milliseconds(durationSeconds: -4) == 1)
    #expect(
        NineGameCenterScore.milliseconds(durationSeconds: 100_000)
            == NineGameCenterScore.maximumDailyMilliseconds
    )
}

@Test func gameCenterAchievementLedgerSuppressesDuplicatesAndRetriesFailures() {
    var ledger = NineAchievementLedger()

    let first = ledger.beginReport(.firstSolve)
    #expect(first)
    let duplicate = ledger.beginReport(.firstSolve)
    #expect(!duplicate)

    ledger.hydrate([NineGameCenterAchievement.tutorialComplete.rawValue])
    let hydratedDuplicate = ledger.beginReport(.tutorialComplete)
    #expect(!hydratedDuplicate)

    let dailyFirst = ledger.beginReport(.firstDaily)
    #expect(dailyFirst)
    ledger.markReportFailed(.firstDaily)
    let dailyRetry = ledger.beginReport(.firstDaily)
    #expect(dailyRetry)
}

@Test func gameCenterIdentifiersStayStable() {
    #expect(NineGameCenterIDs.dailyLeaderboard == "ai.knowlly.nine.daily.time")
    #expect(
        Set(NineGameCenterAchievement.allCases.map(\.rawValue)).count
            == NineGameCenterAchievement.allCases.count
    )
}

private final class CapturingAnalyticsClient: NineAnalyticsClient {
    private(set) var events: [NineAnalyticsEvent] = []

    func track(_ event: NineAnalyticsEvent) {
        events.append(event)
    }
}


@MainActor
@Test func bundledAchievementArtworkExists() {
    for achievement in NineGameCenterAchievement.allCases {
        #expect(UIImage(named: achievement.artworkAssetName) != nil)
    }
}
@Test func capturePresetParserIsDeterministic() {
    #expect(NineCapturePreset.parse(arguments: ["Nine"]) == nil)
    #expect(NineCapturePreset.parse(arguments: ["Nine", "--nine-capture", "simple"]) == .simple)
    #expect(NineCapturePreset.parse(arguments: ["Nine", "--nine-capture", "daily"]) == .daily)
    #expect(NineCapturePreset.parse(arguments: ["Nine", "--nine-capture", "unknown"]) == nil)
}
