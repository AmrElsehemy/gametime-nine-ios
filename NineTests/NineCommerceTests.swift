import Testing
@testable import Nine

@Test func rewardedHintPolicyNeverMonetizesTeaching() {
    #expect(!NineRewardedHintPolicy.isEligible(isTutorial: true, isLevelComplete: false, hasActiveHint: false))
    #expect(!NineRewardedHintPolicy.isEligible(isTutorial: false, isLevelComplete: true, hasActiveHint: false))
    #expect(!NineRewardedHintPolicy.isEligible(isTutorial: false, isLevelComplete: false, hasActiveHint: true))
    #expect(NineRewardedHintPolicy.isEligible(isTutorial: false, isLevelComplete: false, hasActiveHint: false))
}
