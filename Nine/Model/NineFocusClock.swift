import Foundation

/// Integer milliseconds and integer score arithmetic form scoring version 1.
/// Thresholds are inclusive; timeout occurs only after the final threshold.
struct NineFocusTuning: Codable, Equatable, Sendable {
    var threeStarTime: Int
    var twoStarTime: Int
    var oneStarTime: Int
    var baseScore: Int = 1_000
    var cleanSolveBonus: Int = 250
    var noHintBonus: Int = 250
    var timeBonusRate: Int = 10
    var rescueSeconds: Int = 15

    var isValid: Bool {
        threeStarTime > 0 && threeStarTime < twoStarTime && twoStarTime < oneStarTime
        && oneStarTime <= 3_600_000 && (0...1_000_000).contains(baseScore)
        && (0...1_000_000).contains(cleanSolveBonus) && (0...1_000_000).contains(noHintBonus)
        && (0...1_000).contains(timeBonusRate) && (1...120).contains(rescueSeconds)
    }

    static func initial(size: Int, difficulty: Int = 1) -> Self {
        let target = 25_000 + max(0, size - 6) * 10_000 + max(0, difficulty - 1) * 5_000
        return Self(threeStarTime: target, twoStarTime: target + 20_000, oneStarTime: target + 45_000)
    }
}

struct NineMasteryResult: Codable, Equatable, Sendable {
    let scoringVersion: Int
    let elapsedMilliseconds: Int
    let stars: Int
    let score: Int
    let cleanSolve: Bool
    let hintsUsed: Int
    let rescued: Bool
    let restored: Bool
    var isRanked: Bool { !rescued && !restored && hintsUsed == 0 }
}

enum NineFocusPhase: String, Codable, Sendable { case inspecting, running, timedOut, completed }

/// No wall clock, SpriteKit, SDK or animation dependency. The caller supplies a
/// nondecreasing attempt timeline, so events reproduce the same result on replay.
struct NineFocusAttempt: Codable, Equatable, Sendable {
    let tuning: NineFocusTuning
    private(set) var phase: NineFocusPhase = .inspecting
    private(set) var timelineMilliseconds = 0
    private(set) var elapsedMilliseconds = 0
    private(set) var cleanSolve = true
    private(set) var hintsUsed = 0
    private(set) var rescueReceiptID: String?
    private(set) var restored = false
    private(set) var result: NineMasteryResult?

    init(tuning: NineFocusTuning) {
        precondition(tuning.isValid)
        self.tuning = tuning
    }

    var rescued: Bool { rescueReceiptID != nil }
    var deadline: Int { tuning.oneStarTime + (rescued ? tuning.rescueSeconds * 1_000 : 0) }
    var remainingMilliseconds: Int { max(0, deadline - elapsedMilliseconds) }
    var stars: Int {
        guard phase != .timedOut else { return 0 }
        if rescued { return 1 }
        if elapsedMilliseconds <= tuning.threeStarTime { return 3 }
        return elapsedMilliseconds <= tuning.twoStarTime ? 2 : 1
    }
    var canPlay: Bool { phase == .inspecting || phase == .running }

    mutating func advance(to milliseconds: Int) {
        let next = max(timelineMilliseconds, min(86_400_000, max(0, milliseconds)))
        if phase == .running {
            elapsedMilliseconds = min(deadline + 1, elapsedMilliseconds + next - timelineMilliseconds)
            if elapsedMilliseconds > deadline { phase = .timedOut }
        }
        timelineMilliseconds = next
    }

    mutating func committedPlacement(at milliseconds: Int) {
        advance(to: milliseconds)
        if phase == .inspecting { phase = .running }
    }

    mutating func reversal(at milliseconds: Int) {
        advance(to: milliseconds)
        if canPlay { cleanSolve = false }
    }

    mutating func hint(at milliseconds: Int) {
        advance(to: milliseconds)
        if canPlay { hintsUsed += 1 }
    }

    mutating func markRestored() { restored = true }

    @discardableResult
    mutating func rescue(receiptID: String, at milliseconds: Int) -> Bool {
        advance(to: milliseconds)
        guard phase == .timedOut, !rescued, !receiptID.isEmpty else { return false }
        rescueReceiptID = receiptID
        // Exclude failed-screen/ad dwell time. Exactly the configured extension.
        elapsedMilliseconds = tuning.oneStarTime
        phase = .running
        return true
    }

    @discardableResult
    mutating func solve(at milliseconds: Int) -> NineMasteryResult? {
        advance(to: milliseconds)
        guard phase == .running else { return nil }
        let earnedStars = stars
        let score = tuning.baseScore
            + max(0, tuning.oneStarTime - elapsedMilliseconds) * tuning.timeBonusRate / 1_000
            + (cleanSolve ? tuning.cleanSolveBonus : 0)
            + (hintsUsed == 0 ? tuning.noHintBonus : 0)
        result = NineMasteryResult(scoringVersion: 1, elapsedMilliseconds: elapsedMilliseconds,
            stars: earnedStars, score: rescued ? 0 : score, cleanSolve: cleanSolve,
            hintsUsed: hintsUsed, rescued: rescued, restored: restored)
        phase = .completed
        return result
    }
}

/// Ranked PBs cannot be overwritten by assisted or resumed runs. Progress stars
/// may still improve, including the single progression star from rescue.
struct NinePersonalMastery: Codable, Equatable, Sendable {
    var stars = 0
    var best: NineMasteryResult?
    @discardableResult mutating func record(_ result: NineMasteryResult) -> Bool {
        stars = max(stars, result.stars)
        guard result.isRanked else { return false }
        if let best, best.score > result.score || (best.score == result.score && best.elapsedMilliseconds <= result.elapsedMilliseconds) { return false }
        best = result
        return true
    }
}
