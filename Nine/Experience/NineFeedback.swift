import AVFoundation
import CoreHaptics
import Foundation
import UIKit

enum NineFeedbackEvent: String, CaseIterable, Sendable {
    case placement
    case removal
    case invalid
    case hint
    case undo
    case reset
    case solved
    case milestone
}

struct NineFeedbackCue: Equatable, Sendable {
    let hapticIntensity: Float
    let hapticSharpness: Float
    let frequency: Double
    let duration: Double
    let gain: Float

    static func cue(for event: NineFeedbackEvent) -> NineFeedbackCue {
        switch event {
        case .placement:
            return .init(hapticIntensity: 0.48, hapticSharpness: 0.58, frequency: 520, duration: 0.055, gain: 0.13)
        case .removal:
            return .init(hapticIntensity: 0.28, hapticSharpness: 0.30, frequency: 330, duration: 0.045, gain: 0.09)
        case .invalid:
            return .init(hapticIntensity: 0.72, hapticSharpness: 0.84, frequency: 185, duration: 0.085, gain: 0.11)
        case .hint:
            return .init(hapticIntensity: 0.36, hapticSharpness: 0.42, frequency: 660, duration: 0.070, gain: 0.10)
        case .undo:
            return .init(hapticIntensity: 0.24, hapticSharpness: 0.34, frequency: 390, duration: 0.045, gain: 0.08)
        case .reset:
            return .init(hapticIntensity: 0.30, hapticSharpness: 0.24, frequency: 285, duration: 0.070, gain: 0.08)
        case .solved:
            return .init(hapticIntensity: 0.70, hapticSharpness: 0.52, frequency: 780, duration: 0.120, gain: 0.14)
        case .milestone:
            return .init(hapticIntensity: 0.86, hapticSharpness: 0.62, frequency: 920, duration: 0.140, gain: 0.15)
        }
    }
}

struct NineFeedbackPreferences: Equatable, Sendable {
    var soundEnabled: Bool
    var hapticsEnabled: Bool

    static let defaults = NineFeedbackPreferences(
        soundEnabled: true,
        hapticsEnabled: true
    )
}

@MainActor
final class NineFeedbackPreferenceStore {
    private enum Key {
        static let sound = "nine.preferences.soundEnabled"
        static let haptics = "nine.preferences.hapticsEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: NineFeedbackPreferences {
        NineFeedbackPreferences(
            soundEnabled: defaults.object(forKey: Key.sound) == nil
                ? true
                : defaults.bool(forKey: Key.sound),
            hapticsEnabled: defaults.object(forKey: Key.haptics) == nil
                ? true
                : defaults.bool(forKey: Key.haptics)
        )
    }

    func setSoundEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.sound)
    }

    func setHapticsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.haptics)
    }
}

@MainActor
final class NineFeedbackEngine {
    private let preferences: NineFeedbackPreferenceStore
    private var hapticEngine: CHHapticEngine?
    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let audioFormat = AVAudioFormat(
        standardFormatWithSampleRate: 44_100,
        channels: 1
    )!
    private var audioConfigured = false
    private var audioReady = false

    init(preferences: NineFeedbackPreferenceStore = .init()) {
        self.preferences = preferences
        prepareHaptics()
        prepareAudio()
    }

    func play(_ event: NineFeedbackEvent) {
        let settings = preferences.current
        let cue = NineFeedbackCue.cue(for: event)

        if settings.hapticsEnabled {
            playHaptic(event, cue: cue)
        }
        if settings.soundEnabled {
            playTone(cue)
        }
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.hapticEngine?.start()
                }
            }
            try engine.start()
            hapticEngine = engine
        } catch {
            hapticEngine = nil
        }
    }

    private func playHaptic(_ semanticEvent: NineFeedbackEvent, cue: NineFeedbackCue) {
        guard let hapticEngine else {
            playUIKitFallback(semanticEvent)
            return
        }

        let intensity = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: cue.hapticIntensity
        )
        let sharpness = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: cue.hapticSharpness
        )
        let hapticEvent = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensity, sharpness],
            relativeTime: 0
        )

        do {
            try hapticEngine.start()
            let pattern = try CHHapticPattern(events: [hapticEvent], parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            playUIKitFallback(semanticEvent)
        }
    }

    private func playUIKitFallback(_ event: NineFeedbackEvent) {
        switch event {
        case .invalid:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .solved, .milestone:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        default:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func prepareAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])

            if !audioConfigured {
                audioEngine.attach(player)
                audioEngine.connect(player, to: audioEngine.mainMixerNode, format: audioFormat)
                audioConfigured = true
            }

            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            audioReady = true
        } catch {
            audioReady = false
        }
    }

    private func playTone(_ cue: NineFeedbackCue) {
        if !audioReady || !audioEngine.isRunning {
            prepareAudio()
        }
        guard audioReady else { return }

        let frameCount = AVAudioFrameCount(audioFormat.sampleRate * cue.duration)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: frameCount
        ), let samples = buffer.floatChannelData?[0] else {
            return
        }

        buffer.frameLength = frameCount
        let sampleRate = audioFormat.sampleRate
        let attackFrames = max(1, Int(Double(frameCount) * 0.12))

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let phase = 2.0 * Double.pi * cue.frequency * time
            let attack = min(1.0, Double(frame) / Double(attackFrames))
            let release = max(0, 1.0 - Double(frame) / Double(frameCount))
            let envelope = attack * release * release
            let fundamental = sin(phase)
            let overtone = 0.18 * sin(phase * 2.01)
            samples[frame] = Float((fundamental + overtone) * envelope) * cue.gain
        }

        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying {
            player.play()
        }
    }
}

// MARK: - Puzzle assistance primitives

enum NineHintAction: String, Equatable, Sendable {
    case place
    case remove
}

struct NineHint: Equatable, Sendable {
    let action: NineHintAction
    let coordinate: BoardCoordinate
    let reason: String
}

enum NineHintEngine {
    static func nextHint(
        level: PrototypeLevel,
        state: NineBoardState
    ) -> NineHint? {
        let authoredSolution = Set(level.solution)
        let initial = level.initialMarkers
        let evaluation = NineConstraintEngine.evaluate(
            state,
            level: level.definition
        )

        // A rule conflict marks every participant, including correct solution
        // markers. Only tell the player to remove a conflicting marker when that
        // marker is itself outside the unique authored solution.
        if let wrongConflict = evaluation.conflictingCoordinates
            .subtracting(authoredSolution)
            .subtracting(initial)
            .sorted()
            .first {
            return NineHint(
                action: .remove,
                coordinate: wrongConflict,
                reason: "This pebble conflicts with another rule."
            )
        }

        if let wrong = state.markers
            .subtracting(authoredSolution)
            .subtracting(initial)
            .sorted()
            .first {
            return NineHint(
                action: .remove,
                coordinate: wrong,
                reason: "This placement leads away from the unique solution."
            )
        }

        if let missing = level.solution.first(where: {
            !state.markers.contains($0)
        }) {
            return NineHint(
                action: .place,
                coordinate: missing,
                reason: "A useful next placement is highlighted."
            )
        }

        return nil
    }
}

struct NineMoveHistory: Equatable, Sendable {
    private(set) var states: [Set<BoardCoordinate>] = []

    var canUndo: Bool { states.count > 1 }

    mutating func reset(to markers: Set<BoardCoordinate>) {
        states = [markers]
    }

    mutating func record(_ markers: Set<BoardCoordinate>) {
        guard states.last != markers else { return }
        states.append(markers)
    }

    mutating func undo() -> Set<BoardCoordinate>? {
        guard states.count > 1 else { return nil }
        states.removeLast()
        return states.last
    }
}

enum NineGameplayIntentKind: String, Equatable, Sendable {
    case place
    case remove
    case undo
    case reset
    case hintPreview = "hint_preview"
}

struct NineGameplayIntent: Equatable, Sendable {
    let kind: NineGameplayIntentKind
    let levelID: String
    let coordinate: BoardCoordinate?
}

// MARK: - Deterministic replay

struct NineReplayEvent: Codable, Equatable, Sendable {
    let sequence: Int
    let kind: String
    let coordinate: BoardCoordinate?
    var timestampMilliseconds: Int? = nil
}

struct NineReplay: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let replayID: UUID
    let appVersion: String
    let buildVersion: String
    let levelID: String
    let levelSchemaVersion: Int
    let mode: String
    let dayKey: String?
    let initialMarkers: [BoardCoordinate]
    var events: [NineReplayEvent]
    var initialFocus: NineFocusAttempt? = nil
    var focusResult: NineMasteryResult? = nil
    var completedAtMilliseconds: Int? = nil
}

enum NineReplayError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case levelMismatch(expected: String, actual: String)
    case levelSchemaMismatch(expected: Int, actual: Int)
    case malformedEvent(sequence: Int)
}

struct NineReplayRecorder: Sendable {
    private(set) var replay: NineReplay

    init(
        level: PrototypeLevel,
        mode: NinePlayMode,
        dayKey: String?,
        initialMarkers: Set<BoardCoordinate>,
        appVersion: String,
        buildVersion: String,
        replayID: UUID = UUID()
    ) {
        replay = NineReplay(
            schemaVersion: NineReplay.currentSchemaVersion,
            replayID: replayID,
            appVersion: appVersion,
            buildVersion: buildVersion,
            levelID: level.definition.id,
            levelSchemaVersion: level.definition.schemaVersion,
            mode: mode.rawValue,
            dayKey: dayKey,
            initialMarkers: initialMarkers.sorted(),
            events: []
        )
    }

    mutating func setInitialFocus(_ attempt: NineFocusAttempt) { replay.initialFocus = attempt }

    mutating func finishFocus(_ result: NineMasteryResult?, at milliseconds: Int) {
        replay.focusResult = result
        replay.completedAtMilliseconds = result == nil ? nil : milliseconds
    }

    mutating func record(_ intent: NineGameplayIntent, at milliseconds: Int? = nil) {
        guard intent.levelID == replay.levelID else { return }
        replay.events.append(
            NineReplayEvent(
                sequence: replay.events.count,
                kind: intent.kind.rawValue,
                coordinate: intent.coordinate,
                timestampMilliseconds: milliseconds
            )
        )
    }
}

enum NineReplayPlayer {
    static func finalState(
        replay: NineReplay,
        level: PrototypeLevel
    ) throws -> NineBoardState {
        guard (1...NineReplay.currentSchemaVersion).contains(replay.schemaVersion) else {
            throw NineReplayError.unsupportedSchemaVersion(replay.schemaVersion)
        }
        guard replay.levelID == level.definition.id else {
            throw NineReplayError.levelMismatch(
                expected: level.definition.id,
                actual: replay.levelID
            )
        }
        guard replay.levelSchemaVersion == level.definition.schemaVersion else {
            throw NineReplayError.levelSchemaMismatch(
                expected: level.definition.schemaVersion,
                actual: replay.levelSchemaVersion
            )
        }

        var state = NineBoardState(
            level: level.definition,
            markers: Set(replay.initialMarkers)
        )
        var history = NineMoveHistory()
        history.reset(to: state.markers)

        for (index, event) in replay.events.enumerated() {
            guard event.sequence == index,
                  let kind = NineGameplayIntentKind(rawValue: event.kind) else {
                throw NineReplayError.malformedEvent(sequence: event.sequence)
            }

            switch kind {
            case .place:
                guard let coordinate = event.coordinate,
                      state.placeMarker(at: coordinate, level: level.definition) else {
                    throw NineReplayError.malformedEvent(sequence: event.sequence)
                }
                history.record(state.markers)
            case .remove:
                guard let coordinate = event.coordinate,
                      state.removeMarker(at: coordinate) else {
                    throw NineReplayError.malformedEvent(sequence: event.sequence)
                }
                history.record(state.markers)
            case .undo:
                guard let markers = history.undo() else {
                    throw NineReplayError.malformedEvent(sequence: event.sequence)
                }
                state = NineBoardState(level: level.definition, markers: markers)
            case .reset:
                state = NineBoardState(
                    level: level.definition,
                    markers: level.initialMarkers
                )
                history.reset(to: state.markers)
            case .hintPreview:
                break
            }
        }

        return state
    }
}

enum NineReplayCodec {
    static func encode(_ replay: NineReplay) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(replay)
    }

    static func decode(_ data: Data) throws -> NineReplay {
        try JSONDecoder().decode(NineReplay.self, from: data)
    }
}

// MARK: - Diagnostics and support

struct NineDiagnosticBreadcrumb: Codable, Equatable, Sendable {
    let timestamp: Date
    let category: String
    let message: String
}

@MainActor
final class NineDiagnosticsBuffer {
    private let capacity: Int
    private(set) var breadcrumbs: [NineDiagnosticBreadcrumb] = []

    init(capacity: Int = 50) {
        self.capacity = max(1, capacity)
    }

    func add(
        _ category: String,
        _ message: String,
        at timestamp: Date = Date()
    ) {
        breadcrumbs.append(
            NineDiagnosticBreadcrumb(
                timestamp: timestamp,
                category: category,
                message: message
            )
        )
        if breadcrumbs.count > capacity {
            breadcrumbs.removeFirst(breadcrumbs.count - capacity)
        }
    }
}

struct NineSupportPackage: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let appVersion: String
    let buildVersion: String
    let deviceClass: String
    let osClass: String
    let levelID: String?
    let levelSchemaVersion: Int?
    let replay: NineReplay?
    let breadcrumbs: [NineDiagnosticBreadcrumb]
}

@MainActor
enum NineRuntimeMetadata {
    static var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
    }

    static var buildVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
    }

    static var deviceClass: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    static var osClass: String {
        "iOS \(UIDevice.current.systemVersion)"
    }
}

// MARK: - Analytics

enum NineAnalyticsEventName: String, CaseIterable, Sendable {
    case focusStarted = "attempt_timer_started"
    case focusThreshold = "star_threshold"
    case focusTimeout = "fail_timeout"
    case masteryCompleted = "mastery_completed"
    case replay = "replay_from_results"
    case retry = "retry_attempt"
    case firstOpen = "first_open"
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case tutorialStarted = "tutorial_started"
    case tutorialCompleted = "tutorial_completed"
    case levelStarted = "level_started"
    case levelCompleted = "level_completed"
    case levelAbandoned = "level_abandoned"
    case invalidMove = "invalid_move"
    case undo
    case reset
    case hint
    case dailyStarted = "daily_started"
    case dailyCompleted = "daily_completed"
    case rewardOfferShown = "reward_offer_shown"
    case rewardOfferAccepted = "reward_offer_accepted"
    case rewardCompleted = "reward_completed"
    case iapStarted = "iap_started"
    case iapCompleted = "iap_completed"
}

struct NineAnalyticsEvent: Equatable, Sendable {
    let name: NineAnalyticsEventName
    let properties: [String: String]
}

protocol NineAnalyticsClient: AnyObject {
    func track(_ event: NineAnalyticsEvent)
}

final class NineNoOpAnalyticsClient: NineAnalyticsClient {
    func track(_ event: NineAnalyticsEvent) {}
}

final class NineDebugAnalyticsClient: NineAnalyticsClient {
    private let capacity: Int
    private(set) var events: [NineAnalyticsEvent] = []

    init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    func track(_ event: NineAnalyticsEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        #if DEBUG
        print("[NineAnalytics] \(event.name.rawValue) \(event.properties)")
        #endif
    }
}

@MainActor
final class NineAnalyticsLifecycleStore {
    private enum Key {
        static let firstOpenSent = "nine.analytics.firstOpenSent"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldSendFirstOpen: Bool {
        !defaults.bool(forKey: Key.firstOpenSent)
    }

    func markFirstOpenSent() {
        defaults.set(true, forKey: Key.firstOpenSent)
    }
}

@MainActor
final class NineAnalyticsTracker {
    private let client: NineAnalyticsClient
    private let lifecycleStore: NineAnalyticsLifecycleStore
    private var criticalKeys: Set<String> = []

    init(
        client: NineAnalyticsClient = NineNoOpAnalyticsClient(),
        lifecycleStore: NineAnalyticsLifecycleStore = .init()
    ) {
        self.client = client
        self.lifecycleStore = lifecycleStore
    }

    func trackFirstOpenIfNeeded() {
        guard lifecycleStore.shouldSendFirstOpen else { return }
        track(.firstOpen, dedupeKey: "first_open")
        lifecycleStore.markFirstOpenSent()
    }

    func track(
        _ name: NineAnalyticsEventName,
        level: PrototypeLevel? = nil,
        mode: NinePlayMode? = nil,
        durationSeconds: TimeInterval? = nil,
        extra: [String: String] = [:],
        dedupeKey: String? = nil
    ) {
        if let dedupeKey {
            guard criticalKeys.insert(dedupeKey).inserted else { return }
        }

        var properties: [String: String] = [
            "app_version": NineRuntimeMetadata.appVersion,
            "build_version": NineRuntimeMetadata.buildVersion
        ]

        if let level {
            properties["level_id"] = level.definition.id
            properties["level_version"] = String(level.definition.schemaVersion)
            properties["board_size"] = String(level.definition.size)
        }
        if let mode {
            properties["mode"] = mode.rawValue
        }
        if let durationSeconds {
            properties["duration_ms"] = String(Int(max(0, durationSeconds) * 1_000))
        }
        for (key, value) in extra {
            properties[key] = value
        }

        client.track(
            NineAnalyticsEvent(name: name, properties: properties)
        )
    }

    func resetSessionDeduplication() {
        criticalKeys = criticalKeys.filter { $0 == "first_open" }
    }
}

extension NineReplayPlayer {
    /// Recomputes scoring from timed logical input, never from animation duration.
    /// Legacy recordings remain playable but cannot establish ranked mastery.
    static func masteryResult(replay: NineReplay, level: PrototypeLevel) throws -> NineMasteryResult? {
        guard replay.schemaVersion == 2, var attempt = replay.initialFocus,
              attempt.tuning == level.focusTuning,
              let completedAt = replay.completedAtMilliseconds else { return nil }
        let final = try finalState(replay: replay, level: level)
        guard NineConstraintEngine.evaluate(final, level: level.definition).isSolved else {
            throw NineReplayError.malformedEvent(sequence: replay.events.count)
        }
        for event in replay.events {
            guard let timestamp = event.timestampMilliseconds,
                  timestamp >= attempt.timelineMilliseconds,
                  let kind = NineGameplayIntentKind(rawValue: event.kind) else {
                throw NineReplayError.malformedEvent(sequence: event.sequence)
            }
            attempt.advance(to: timestamp)
            guard attempt.canPlay else { throw NineReplayError.malformedEvent(sequence: event.sequence) }
            switch kind {
            case .place: attempt.committedPlacement(at: timestamp)
            case .remove, .undo: attempt.reversal(at: timestamp)
            case .hintPreview: attempt.hint(at: timestamp)
            case .reset: throw NineReplayError.malformedEvent(sequence: event.sequence)
            }
        }
        guard completedAt >= attempt.timelineMilliseconds,
              let result = attempt.solve(at: completedAt), result == replay.focusResult else {
            throw NineReplayError.malformedEvent(sequence: replay.events.count)
        }
        return result
    }
}
