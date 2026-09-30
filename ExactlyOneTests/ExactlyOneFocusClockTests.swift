import XCTest
@testable import ExactlyOne

final class ExactlyOneFocusClockTests: XCTestCase {
    private let tuning = ExactlyOneFocusTuning(threeStarTime: 1_000, twoStarTime: 2_000, oneStarTime: 3_000)

    func testInspectionIsFreeAndFirstCommittedPlacementStartsClock() {
        var attempt = ExactlyOneFocusAttempt(tuning: tuning)
        attempt.advance(to: 50_000)
        XCTAssertEqual(attempt.elapsedMilliseconds, 0)
        attempt.committedPlacement(at: 60_000)
        attempt.advance(to: 60_250)
        XCTAssertEqual(attempt.elapsedMilliseconds, 250)
        XCTAssertEqual(attempt.phase, .running)
    }

    func testInclusiveThresholdsAndEverySolveEarnsAtLeastOneStar() {
        for (time, stars) in [(1_000, 3), (1_001, 2), (2_000, 2), (2_001, 1), (3_000, 1), (3_001, 1), (600_000, 1)] {
            var attempt = ExactlyOneFocusAttempt(tuning: tuning)
            attempt.committedPlacement(at: 0)
            XCTAssertEqual(attempt.solve(at: time)?.stars, stars)
            XCTAssertEqual(attempt.phase, .completed)
        }
    }

    func testCleanSolveHintsAndIntegerScore() {
        var attempt = ExactlyOneFocusAttempt(tuning: tuning)
        attempt.committedPlacement(at: 0)
        XCTAssertEqual(attempt.solve(at: 1_250)?.score, 1_517)
        var assisted = ExactlyOneFocusAttempt(tuning: tuning)
        assisted.committedPlacement(at: 0)
        assisted.reversal(at: 100)
        assisted.hint(at: 200)
        let result = assisted.solve(at: 1_250)
        XCTAssertEqual(result?.score, 1_017)
        XCTAssertEqual(result?.isRanked, false)
    }

    func testSlowUnassistedSolveIsRankedOneStarWithoutTimeBonus() {
        var attempt = ExactlyOneFocusAttempt(tuning: tuning)
        attempt.committedPlacement(at: 0)
        attempt.advance(to: 50_000)
        XCTAssertTrue(attempt.canPlay)
        let result = attempt.solve(at: 51_000)!
        XCTAssertEqual(result.stars, 1)
        XCTAssertEqual(result.score, 1_500)
        XCTAssertTrue(result.isRanked)
        var mastery = ExactlyOnePersonalMastery()
        XCTAssertTrue(mastery.record(result))
        XCTAssertEqual(mastery.stars, 1)
    }

    func testRoundTripPreservesTiming() throws {
        var attempt = ExactlyOneFocusAttempt(tuning: tuning)
        attempt.committedPlacement(at: 0)
        attempt.hint(at: 400)
        var decoded = try JSONDecoder().decode(ExactlyOneFocusAttempt.self, from: JSONEncoder().encode(attempt))
        XCTAssertEqual(attempt.solve(at: 900), decoded.solve(at: 900))
        var restored = ExactlyOneFocusAttempt(tuning: tuning)
        restored.markRestored()
        restored.committedPlacement(at: 0)
        XCTAssertFalse(restored.solve(at: 0)!.isRanked)
    }

    func testBackwardTimeCannotRewindAndCompletedStateIsTerminal() {
        var attempt = ExactlyOneFocusAttempt(tuning: tuning)
        attempt.committedPlacement(at: 100)
        attempt.advance(to: 900)
        attempt.advance(to: 200)
        XCTAssertEqual(attempt.elapsedMilliseconds, 800)
        let result = attempt.solve(at: 900)
        attempt.advance(to: 100_000)
        XCTAssertEqual(attempt.result, result)
        XCTAssertFalse(attempt.canPlay)
        XCTAssertNil(attempt.solve(at: 100_000))
    }
}
