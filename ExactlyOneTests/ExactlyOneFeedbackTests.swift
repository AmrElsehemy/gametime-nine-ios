import Foundation
import UIKit
import Testing
@testable import ExactlyOne

@Test func semanticFeedbackCuesAreDistinctAndBounded() {
    let placement = ExactlyOneFeedbackCue.cue(for: .placement)
    let invalid = ExactlyOneFeedbackCue.cue(for: .invalid)
    let solved = ExactlyOneFeedbackCue.cue(for: .solved)

    #expect(placement != invalid)
    #expect(invalid != solved)
    #expect(invalid.hapticIntensity > placement.hapticIntensity)
    #expect(solved.frequency > placement.frequency)

    for event in ExactlyOneFeedbackEvent.allCases {
        let cue = ExactlyOneFeedbackCue.cue(for: event)
        #expect((0...1).contains(cue.hapticIntensity))
        #expect((0...1).contains(cue.hapticSharpness))
        #expect(cue.frequency > 0)
        #expect(cue.duration > 0)
        #expect(cue.gain > 0)
    }
}

@MainActor
@Test func soundAndHapticsPreferencesPersistIndependently() {
    let suiteName = "ExactlyOneFeedbackTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = ExactlyOneFeedbackPreferenceStore(defaults: defaults)
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

    var state = ExactlyOneBoardState(
        level: level.definition,
        markers: level.initialMarkers
    )
    var history = ExactlyOneMoveHistory()
    history.reset(to: state.markers)

    var recorder = ExactlyOneReplayRecorder(
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
        ExactlyOneGameplayIntent(
            kind: .place,
            levelID: level.definition.id,
            coordinate: first
        )
    )

    let placedSecond = state.placeMarker(at: second, level: level.definition)
    #expect(placedSecond)
    history.record(state.markers)
    recorder.record(
        ExactlyOneGameplayIntent(
            kind: .place,
            levelID: level.definition.id,
            coordinate: second
        )
    )

    let undoResult = history.undo()
    let undoMarkers = try #require(undoResult)
    state = ExactlyOneBoardState(level: level.definition, markers: undoMarkers)
    recorder.record(
        ExactlyOneGameplayIntent(
            kind: .undo,
            levelID: level.definition.id,
            coordinate: nil
        )
    )

    let replacedSecond = state.placeMarker(at: second, level: level.definition)
    #expect(replacedSecond)
    history.record(state.markers)
    recorder.record(
        ExactlyOneGameplayIntent(
            kind: .place,
            levelID: level.definition.id,
            coordinate: second
        )
    )
    recorder.record(
        ExactlyOneGameplayIntent(
            kind: .hintPreview,
            levelID: level.definition.id,
            coordinate: nil
        )
    )

    let encoded = try ExactlyOneReplayCodec.encode(recorder.replay)
    let decoded = try ExactlyOneReplayCodec.decode(encoded)
    let replayed = try ExactlyOneReplayPlayer.finalState(replay: decoded, level: level)

    #expect(decoded == recorder.replay)
    #expect(replayed.markers == state.markers)
    #expect(decoded.schemaVersion == ExactlyOneReplay.currentSchemaVersion)
    #expect(decoded.levelID == level.definition.id)
    #expect(decoded.levelSchemaVersion == level.definition.schemaVersion)
    #expect(decoded.appVersion == "1.0")
    #expect(decoded.buildVersion == "42")
    #expect(decoded.events.map(\.sequence) == Array(0..<decoded.events.count))
}

@Test func replayRejectsUnsupportedOrMalformedInputGracefully() throws {
    let level = PrototypeLevels.production[5]
    let replayID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!

    let incompatible = ExactlyOneReplay(
        schemaVersion: 999,
        replayID: replayID,
        appVersion: "1.0",
        buildVersion: "42",
        levelID: level.definition.id,
        levelSchemaVersion: level.definition.schemaVersion,
        mode: ExactlyOnePlayMode.progression.rawValue,
        dayKey: nil,
        initialMarkers: level.initialMarkers.sorted(),
        events: []
    )

    #expect(throws: ExactlyOneReplayError.unsupportedSchemaVersion(999)) {
        _ = try ExactlyOneReplayPlayer.finalState(replay: incompatible, level: level)
    }

    let malformed = ExactlyOneReplay(
        schemaVersion: ExactlyOneReplay.currentSchemaVersion,
        replayID: replayID,
        appVersion: "1.0",
        buildVersion: "42",
        levelID: level.definition.id,
        levelSchemaVersion: level.definition.schemaVersion,
        mode: ExactlyOnePlayMode.progression.rawValue,
        dayKey: nil,
        initialMarkers: level.initialMarkers.sorted(),
        events: [
            ExactlyOneReplayEvent(
                sequence: 7,
                kind: ExactlyOneGameplayIntentKind.place.rawValue,
                coordinate: level.solution.first
            )
        ]
    )

    #expect(throws: ExactlyOneReplayError.malformedEvent(sequence: 7)) {
        _ = try ExactlyOneReplayPlayer.finalState(replay: malformed, level: level)
    }
}

@MainActor
@Test func diagnosticsAreBoundedAndSupportPayloadIsPrivacySafeByConstruction() throws {
    let buffer = ExactlyOneDiagnosticsBuffer(capacity: 2)
    buffer.add("level", "loaded:v1-001", at: Date(timeIntervalSince1970: 1))
    buffer.add("save", "saved:v1-001", at: Date(timeIntervalSince1970: 2))
    buffer.add("level", "completed:v1-001", at: Date(timeIntervalSince1970: 3))

    #expect(buffer.breadcrumbs.count == 2)
    #expect(buffer.breadcrumbs.first?.message == "saved:v1-001")
    #expect(buffer.breadcrumbs.last?.message == "completed:v1-001")

    let package = ExactlyOneSupportPackage(
        schemaVersion: ExactlyOneSupportPackage.currentSchemaVersion,
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
    let decoded = try JSONDecoder().decode(ExactlyOneSupportPackage.self, from: data)
    let json = String(decoding: data, as: UTF8.self)

    #expect(decoded == package)
    #expect(!json.contains("email"))
    #expect(!json.contains("playerName"))
    #expect(!json.contains("deviceName"))
    #expect(decoded.breadcrumbs.count == 2)
}

@Test func analyticsSchemaIncludesRequiredLaunchFunnelAndCommerceHooks() {
    let actual = Set(ExactlyOneAnalyticsEventName.allCases.map(\.rawValue))
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
    let suiteName = "ExactlyOneAnalyticsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let client = CapturingAnalyticsClient()
    let lifecycle = ExactlyOneAnalyticsLifecycleStore(defaults: defaults)
    let tracker = ExactlyOneAnalyticsTracker(client: client, lifecycleStore: lifecycle)

    tracker.trackFirstOpenIfNeeded()
    tracker.trackFirstOpenIfNeeded()
    tracker.track(.sessionStart, dedupeKey: "session_start")
    tracker.track(.sessionStart, dedupeKey: "session_start")

    #expect(client.events.map(\.name) == [.firstOpen, .sessionStart])

    let secondClient = CapturingAnalyticsClient()
    let secondTracker = ExactlyOneAnalyticsTracker(
        client: secondClient,
        lifecycleStore: ExactlyOneAnalyticsLifecycleStore(defaults: defaults)
    )
    secondTracker.trackFirstOpenIfNeeded()
    #expect(secondClient.events.isEmpty)
}

@MainActor
@Test func analyticsAddsUsefulLevelDimensionsWithoutBoardCoordinates() {
    let client = CapturingAnalyticsClient()
    let tracker = ExactlyOneAnalyticsTracker(client: client)
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
    #expect(event.properties["mode"] == ExactlyOnePlayMode.progression.rawValue)
    #expect(event.properties["duration_ms"] == "1234")
    #expect(event.properties["reason"] == "solved")
    #expect(event.properties["row"] == nil)
    #expect(event.properties["column"] == nil)
}

@Test func gameCenterScoreConvertsToClampedMilliseconds() {
    #expect(ExactlyOneGameCenterScore.milliseconds(durationSeconds: 1.234) == 1_234)
    #expect(ExactlyOneGameCenterScore.milliseconds(durationSeconds: 0) == 1)
    #expect(ExactlyOneGameCenterScore.milliseconds(durationSeconds: -4) == 1)
    #expect(
        ExactlyOneGameCenterScore.milliseconds(durationSeconds: 100_000)
            == ExactlyOneGameCenterScore.maximumDailyMilliseconds
    )
}

@Test func gameCenterAchievementLedgerSuppressesDuplicatesAndRetriesFailures() {
    var ledger = ExactlyOneAchievementLedger()

    let first = ledger.beginReport(.firstSolve)
    #expect(first)
    let duplicate = ledger.beginReport(.firstSolve)
    #expect(!duplicate)

    ledger.hydrate([ExactlyOneGameCenterAchievement.tutorialComplete.rawValue])
    let hydratedDuplicate = ledger.beginReport(.tutorialComplete)
    #expect(!hydratedDuplicate)

    let dailyFirst = ledger.beginReport(.firstDaily)
    #expect(dailyFirst)
    ledger.markReportFailed(.firstDaily)
    let dailyRetry = ledger.beginReport(.firstDaily)
    #expect(dailyRetry)
}

@Test func gameCenterIdentifiersStayStable() {
    #expect(ExactlyOneGameCenterIDs.dailyLeaderboard == "ai.knowlly.exactlyone.daily.time")
    #expect(
        Set(ExactlyOneGameCenterAchievement.allCases.map(\.rawValue)).count
            == ExactlyOneGameCenterAchievement.allCases.count
    )
}

private final class CapturingAnalyticsClient: ExactlyOneAnalyticsClient {
    private(set) var events: [ExactlyOneAnalyticsEvent] = []

    func track(_ event: ExactlyOneAnalyticsEvent) {
        events.append(event)
    }
}


@MainActor
@Test func bundledAchievementArtworkExists() {
    for achievement in ExactlyOneGameCenterAchievement.allCases {
        #expect(UIImage(named: achievement.artworkAssetName) != nil)
    }
}
@Test func capturePresetParserIsDeterministic() {
    #expect(ExactlyOneCapturePreset.parse(arguments: ["ExactlyOne"]) == nil)
    #expect(ExactlyOneCapturePreset.parse(arguments: ["ExactlyOne", "--exactly-one-capture", "simple"]) == .simple)
    #expect(ExactlyOneCapturePreset.parse(arguments: ["ExactlyOne", "--exactly-one-capture", "daily"]) == .daily)
    #expect(ExactlyOneCapturePreset.parse(arguments: ["ExactlyOne", "--exactly-one-capture", "unknown"]) == nil)
}
