import Foundation
import GameTimeCommerce
import GoogleMobileAds

struct NineAdMobConfiguration: Equatable, Sendable {
    static let googleTestAppID = "ca-app-pub-3940256099942544~1458002511"
    static let googleTestRewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    let rewardedAdUnitID: String
    let usesTestInventory: Bool

    static var current: NineAdMobConfiguration? {
        #if DEBUG
        return .init(
            rewardedAdUnitID: googleTestRewardedAdUnitID,
            usesTestInventory: true
        )
        #else
        guard let adUnitID = Bundle.main.object(
            forInfoDictionaryKey: "NineRewardedAdUnitID"
        ) as? String,
        !adUnitID.isEmpty,
        !adUnitID.contains("3940256099942544") else {
            return nil
        }
        return .init(rewardedAdUnitID: adUnitID, usesTestInventory: false)
        #endif
    }
}

enum NineRewardedHintPolicy {
    static func isEligible(
        isTutorial: Bool,
        isLevelComplete: Bool,
        hasActiveHint: Bool
    ) -> Bool {
        !isTutorial && !isLevelComplete && !hasActiveHint
    }
}

enum NineRewardedHintOutcome: Equatable, Sendable {
    case granted
    case alreadyGranted
    case unavailable
    case notEarned
    case failed
}

actor NineRewardedHintService {
    private let coordinator: RewardedAdCoordinator

    init(
        provider: any RewardedAdProviding = NineAdMobRewardedProvider(),
        receipts: any RewardReceiptPersisting = NineRewardReceiptStore()
    ) {
        coordinator = RewardedAdCoordinator(
            provider: provider,
            receipts: receipts
        )
    }

    func earnHint(rewardID: String) async -> NineRewardedHintOutcome {
        let request = RewardRequest(
            id: rewardID,
            offer: RewardOffer(
                id: "nine.rewarded_hint",
                kind: "hint",
                amount: 1
            )
        )

        do {
            switch try await coordinator.attempt(request) {
            case .granted:
                return .granted
            case .alreadyGranted:
                return .alreadyGranted
            case .unavailable:
                return .unavailable
            case .notEarned:
                return .notEarned
            }
        } catch {
            return .failed
        }
    }
}

actor NineRewardReceiptStore: RewardReceiptPersisting {
    private let key = "nine.commerce.rewardReceipts.v1"

    func contains(rewardID: String) async -> Bool {
        load()[rewardID] != nil
    }

    func record(_ transaction: RewardTransaction) async throws -> Bool {
        var receipts = load()
        guard receipts[transaction.rewardID] == nil else {
            return false
        }
        receipts[transaction.rewardID] = transaction
        let data = try JSONEncoder().encode(receipts)
        UserDefaults.standard.set(data, forKey: key)
        return true
    }

    private func load() -> [String: RewardTransaction] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(
                [String: RewardTransaction].self,
                from: data
              ) else {
            return [:]
        }
        return decoded
    }
}

actor NineAdMobRewardedProvider: RewardedAdProviding {
    func isAvailable(for offer: RewardOffer) async -> Bool {
        guard let configuration = NineAdMobConfiguration.current else {
            return false
        }
        return await NineAdMobController.shared.prepare(
            adUnitID: configuration.rewardedAdUnitID
        )
    }

    func present(offer: RewardOffer) async throws -> Bool {
        guard let configuration = NineAdMobConfiguration.current else {
            return false
        }
        return try await NineAdMobController.shared.present(
            adUnitID: configuration.rewardedAdUnitID
        )
    }
}

@MainActor
private final class NineAdMobController: NSObject, FullScreenContentDelegate {
    static let shared = NineAdMobController()

    private var rewardedAd: RewardedAd?
    private var loadedAdUnitID: String?
    private var didStartSDK = false
    private var didEarnReward = false
    private var pendingPresentation: CheckedContinuation<Bool, Error>?

    func prepare(adUnitID: String) async -> Bool {
        startSDKIfNeeded()

        if rewardedAd != nil, loadedAdUnitID == adUnitID {
            return true
        }

        do {
            let ad = try await RewardedAd.load(
                with: adUnitID,
                request: Request()
            )
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            loadedAdUnitID = adUnitID
            return true
        } catch {
            rewardedAd = nil
            loadedAdUnitID = nil
            return false
        }
    }

    func present(adUnitID: String) async throws -> Bool {
        guard pendingPresentation == nil else {
            return false
        }

        guard await prepare(adUnitID: adUnitID),
              let ad = rewardedAd else {
            return false
        }

        didEarnReward = false

        return try await withCheckedThrowingContinuation { continuation in
            pendingPresentation = continuation
            ad.present(from: nil) { [weak self] in
                self?.didEarnReward = true
            }
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let earned = didEarnReward
        finishPresentation(.success(earned))
        rewardedAd = nil
        loadedAdUnitID = nil
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        finishPresentation(.failure(error))
        rewardedAd = nil
        loadedAdUnitID = nil
    }

    private func startSDKIfNeeded() {
        guard !didStartSDK else { return }
        didStartSDK = true
        MobileAds.shared.start()
    }

    private func finishPresentation(_ result: Result<Bool, Error>) {
        guard let continuation = pendingPresentation else { return }
        pendingPresentation = nil
        didEarnReward = false

        switch result {
        case .success(let earned):
            continuation.resume(returning: earned)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
