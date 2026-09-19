import Foundation
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
