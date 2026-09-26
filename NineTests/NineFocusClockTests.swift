import XCTest
@testable import Nine

final class NineFocusClockTests: XCTestCase {
    private let tuning = NineFocusTuning(threeStarTime: 1_000, twoStarTime: 2_000, oneStarTime: 3_000)

    func testInspectionIsFreeAndFirstCommittedPlacementStartsClock() {
        var attempt = NineFocusAttempt(tuning: tuning)
        attempt.advance(to: 50_000)
        XCTAssertEqual(attempt.elapsedMilliseconds, 0)
        attempt.committedPlacement(at: 60_000)
        attempt.advance(to: 60_250)
        XCTAssertEqual(attempt.elapsedMilliseconds, 250)
        XCTAssertEqual(attempt.phase, .running)
    }

    func testInclusiveThresholdsAndTimeoutCannotBeSolved() {
        for (time, stars) in [(1_000, 3), (1_001, 2), (2_000, 2), (2_001, 1), (3_000, 1)] {
            var attempt = NineFocusAttempt(tuning: tuning)
            attempt.committedPlacement(at: 0)
            XCTAssertEqual(attempt.solve(at: time)?.stars, stars)
        }
        var attempt = NineFocusAttempt(tuning: tuning)
        attempt.committedPlacement(at: 0)
        XCTAssertNil(attempt.solve(at: 3_001))
        XCTAssertEqual(attempt.phase, .timedOut)
    }

    func testCleanSolveHintsAndIntegerScore() {
        var attempt = NineFocusAttempt(tuning: tuning)
        attempt.committedPlacement(at: 0)
        XCTAssertEqual(attempt.solve(at: 1_250)?.score, 1_517)
        var assisted = NineFocusAttempt(tuning: tuning)
        assisted.committedPlacement(at: 0)
        assisted.reversal(at: 100)
        assisted.hint(at: 200)
        let result = assisted.solve(at: 1_250)
        XCTAssertEqual(result?.score, 1_017)
        XCTAssertEqual(result?.isRanked, false)
    }

    func testRescueExactlyOnceDoesNotIncludeAdDwellOrBuyMastery() {
        var attempt = NineFocusAttempt(tuning: tuning)
        attempt.committedPlacement(at: 0)
        attempt.advance(to: 3_001)
        XCTAssertTrue(attempt.rescue(receiptID: "earned", at: 50_000))
        XCTAssertEqual(attempt.remainingMilliseconds, 15_000)
        XCTAssertFalse(attempt.rescue(receiptID: "duplicate", at: 50_000))
        let result = attempt.solve(at: 51_000)!
        XCTAssertEqual(result.stars, 1)
        XCTAssertEqual(result.score, 0)
        XCTAssertFalse(result.isRanked)
        var mastery = NinePersonalMastery()
        XCTAssertFalse(mastery.record(result))
        XCTAssertNil(mastery.best)
        XCTAssertEqual(mastery.stars, 1)
    }

    func testRoundTripPreservesTimingAndRescueIntegrity() throws {
        var attempt = NineFocusAttempt(tuning: tuning)
        attempt.committedPlacement(at: 0)
        attempt.hint(at: 400)
        var decoded = try JSONDecoder().decode(NineFocusAttempt.self, from: JSONEncoder().encode(attempt))
        XCTAssertEqual(attempt.solve(at: 900), decoded.solve(at: 900))
        var restored = NineFocusAttempt(tuning: tuning)
        restored.markRestored()
        restored.committedPlacement(at: 0)
        XCTAssertFalse(restored.solve(at: 0)!.isRanked)
    }

    func testBackwardTimeCannotRewindAndCompletedStateIsTerminal() {
        var attempt = NineFocusAttempt(tuning: tuning)
        attempt.committedPlacement(at: 100)
        attempt.advance(to: 900)
        attempt.advance(to: 200)
        XCTAssertEqual(attempt.elapsedMilliseconds, 800)
        let result = attempt.solve(at: 900)
        attempt.advance(to: 100_000)
        XCTAssertEqual(attempt.result, result)
        XCTAssertFalse(attempt.rescue(receiptID: "late", at: 100_000))
    }
}
