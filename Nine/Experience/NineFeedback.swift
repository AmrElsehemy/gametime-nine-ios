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
    /// Returns one deterministic preview action without mutating the board.
    /// Wrong/conflicting player markers are removed before a solution cell is revealed.
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

        if let conflict = evaluation.conflictingCoordinates
            .subtracting(initial)
            .sorted()
            .first {
            return NineHint(
                action: .remove,
                coordinate: conflict,
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
