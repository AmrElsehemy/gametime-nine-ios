import Testing
import Foundation
import GameTimeCore

@Test func gameTimeKitIsConnected() {
    #expect(!GameTimeKit.version.isEmpty)
}

@Test func approvedPublicDisplayNameIsBundled() {
    #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Exactly One")
    #expect(Bundle.main.bundleIdentifier == "ai.knowlly.gametime.nine")
}
