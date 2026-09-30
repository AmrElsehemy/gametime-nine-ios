import Foundation
import GameKit
import UIKit

enum ExactlyOneGameCenterIDs {
    static let dailyLeaderboard = "ai.knowlly.exactlyone.daily.time"
}

enum ExactlyOneGameCenterAchievement: String, CaseIterable, Sendable {
    case firstSolve = "ai.knowlly.exactlyone.achievement.first-solve"
    case tutorialComplete = "ai.knowlly.exactlyone.achievement.tutorial-complete"
    case firstDaily = "ai.knowlly.exactlyone.achievement.first-daily"
    case streakSeven = "ai.knowlly.exactlyone.achievement.streak-7"
}

struct ExactlyOneAchievementLedger: Equatable, Sendable {
    private(set) var completedIdentifiers: Set<String> = []

    mutating func hydrate(_ identifiers: some Sequence<String>) {
        completedIdentifiers.formUnion(identifiers)
    }

    mutating func beginReport(_ achievement: ExactlyOneGameCenterAchievement) -> Bool {
        completedIdentifiers.insert(achievement.rawValue).inserted
    }

    mutating func markReportFailed(_ achievement: ExactlyOneGameCenterAchievement) {
        completedIdentifiers.remove(achievement.rawValue)
    }
}

enum ExactlyOneGameCenterScore {
    static let maximumDailyMilliseconds = 86_400_000

    static func milliseconds(durationSeconds: TimeInterval) -> Int {
        guard durationSeconds.isFinite else { return maximumDailyMilliseconds }
        let raw = Int((max(0, durationSeconds) * 1_000).rounded())
        return min(maximumDailyMilliseconds, max(1, raw))
    }
}

@MainActor
final class ExactlyOneGameCenterService {
    static let shared = ExactlyOneGameCenterService()

    private(set) var isAuthenticated = false
    private var authenticationRequested = false
    private var achievementLedger = ExactlyOneAchievementLedger()

    var diagnosticHandler: ((String) -> Void)?

    private init() {}

    func authenticateIfNeeded() {
        guard !authenticationRequested else { return }
        authenticationRequested = true

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            MainActor.assumeIsolated {
                guard let self else { return }

                if let viewController {
                    self.presentAuthentication(viewController)
                    return
                }

                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                GKAccessPoint.shared.location = .topLeading
                GKAccessPoint.shared.isActive = self.isAuthenticated

                if let error {
                    self.diagnosticHandler?("auth_failed:\(error.localizedDescription)")
                } else if self.isAuthenticated {
                    self.diagnosticHandler?("authenticated")
                    self.loadCompletedAchievements()
                } else {
                    self.diagnosticHandler?("auth_unavailable_or_declined")
                }
            }
        }
    }

    func report(_ achievement: ExactlyOneGameCenterAchievement) {
        guard isAuthenticated else { return }
        guard achievementLedger.beginReport(achievement) else { return }

        let value = GKAchievement(identifier: achievement.rawValue)
        value.percentComplete = 100
        value.showsCompletionBanner = true

        GKAchievement.report([value]) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.achievementLedger.markReportFailed(achievement)
                    self.diagnosticHandler?(
                        "achievement_failed:\(achievement.rawValue):\(error.localizedDescription)"
                    )
                } else {
                    self.diagnosticHandler?("achievement_reported:\(achievement.rawValue)")
                }
            }
        }
    }

    func submitDailySolve(result: ExactlyOneMasteryResult) {
        guard isAuthenticated, result.isRanked, result.scoringVersion == 1 else { return }
        let durationSeconds = Double(result.elapsedMilliseconds) / 1_000

        let score = ExactlyOneGameCenterScore.milliseconds(
            durationSeconds: durationSeconds
        )

        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [ExactlyOneGameCenterIDs.dailyLeaderboard]
        ) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.diagnosticHandler?(
                        "daily_score_failed:\(error.localizedDescription)"
                    )
                } else {
                    self.diagnosticHandler?("daily_score_submitted:\(score)")
                }
            }
        }
    }

    private func loadCompletedAchievements() {
        GKAchievement.loadAchievements { [weak self] achievements, error in
            MainActor.assumeIsolated {
                guard let self else { return }

                if let error {
                    self.diagnosticHandler?(
                        "achievement_load_failed:\(error.localizedDescription)"
                    )
                    return
                }

                let completed = (achievements ?? [])
                    .filter { $0.percentComplete >= 100 }
                    .map(\.identifier)
                self.achievementLedger.hydrate(completed)
            }
        }
    }

    private func presentAuthentication(_ viewController: UIViewController) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = windowScene.windows
                .first(where: \.isKeyWindow)?
                .rootViewController else {
            diagnosticHandler?("auth_ui_unavailable")
            return
        }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(viewController, animated: true)
    }
}


extension ExactlyOneGameCenterAchievement {
    var artworkAssetName: String {
        switch self {
        case .firstSolve: return "Achievements/FirstSolve"
        case .tutorialComplete: return "Achievements/TutorialComplete"
        case .firstDaily: return "Achievements/FirstDaily"
        case .streakSeven: return "Achievements/Streak7"
        }
    }
}
