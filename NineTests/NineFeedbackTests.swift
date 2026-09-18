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
