from pathlib import Path

p = Path('Nine/GameScene.swift')
s = p.read_text()

s = s.replace(
    '        static let daily = "action:daily"\n        static let cellPrefix = "cell:"',
    '        static let daily = "action:daily"\n        static let rewardAccept = "action:rewardAccept"\n        static let rewardDecline = "action:rewardDecline"\n        static let cellPrefix = "cell:"'
)

s = s.replace(
    '    private var moveHistory = NineMoveHistory()\n    private var activeHint: NineHint?\n    private var emittedGameplayIntents: [NineGameplayIntent] = []',
    '    private var moveHistory = NineMoveHistory()\n    private var activeHint: NineHint?\n    private var emittedGameplayIntents: [NineGameplayIntent] = []\n    private let rewardedHintService = NineRewardedHintService()\n    private var isRewardOfferVisible = false\n    private var isRewardRequestInFlight = false'
)

old_touch = '''        if hitNodes.contains(where: { $0.name == NodeName.hint }) {
            previewHint()
            return
        }'''
new_touch = '''        if hitNodes.contains(where: { $0.name == NodeName.rewardAccept }) {
            acceptRewardedHintOffer()
            return
        }

        if hitNodes.contains(where: { $0.name == NodeName.rewardDecline }) {
            declineRewardedHintOffer()
            return
        }

        if isRewardOfferVisible || isRewardRequestInFlight {
            return
        }

        if hitNodes.contains(where: { $0.name == NodeName.hint }) {
            requestHint()
            return
        }'''
if old_touch not in s:
    raise SystemExit('hint touch block missing')
s = s.replace(old_touch, new_touch, 1)

marker = '    private func previewHint() {'
replacement = '''    private var isInitialTeaching: Bool {
        playMode == .progression
            && tutorialSession.isActive
            && levelIndex < tutorialLevelCount
    }

    private func requestHint() {
        guard !isLevelComplete, activeHint == nil else { return }

        if isInitialTeaching {
            previewHint()
            return
        }

        guard NineRewardedHintPolicy.isEligible(
            isTutorial: isInitialTeaching,
            isLevelComplete: isLevelComplete,
            hasActiveHint: activeHint != nil
        ) else {
            return
        }

        isRewardOfferVisible = true
        analytics.track(
            .rewardOfferShown,
            level: currentLevel,
            mode: playMode,
            durationSeconds: max(0, uptime - levelStartedAt),
            extra: ["reward_kind": "hint"]
        )
        diagnostics.add("commerce", "rewarded_hint_offer_shown")
        renderScene()
    }

    private func declineRewardedHintOffer() {
        guard isRewardOfferVisible, !isRewardRequestInFlight else { return }
        isRewardOfferVisible = false
        diagnostics.add("commerce", "rewarded_hint_offer_declined")
        renderScene()
    }

    private func acceptRewardedHintOffer() {
        guard isRewardOfferVisible, !isRewardRequestInFlight else { return }
        isRewardOfferVisible = false
        isRewardRequestInFlight = true

        analytics.track(
            .rewardOfferAccepted,
            level: currentLevel,
            mode: playMode,
            durationSeconds: max(0, uptime - levelStartedAt),
            extra: ["reward_kind": "hint"]
        )
        diagnostics.add("commerce", "rewarded_hint_offer_accepted")
        renderScene()

        let rewardID = "nine.hint.\\(analyticsAttemptID.uuidString)"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await rewardedHintService.earnHint(rewardID: rewardID)
            isRewardRequestInFlight = false

            switch outcome {
            case .granted, .alreadyGranted:
                analytics.track(
                    .rewardCompleted,
                    level: currentLevel,
                    mode: playMode,
                    durationSeconds: max(0, uptime - levelStartedAt),
                    extra: [
                        "reward_kind": "hint",
                        "outcome": outcome == .granted ? "granted" : "already_granted"
                    ],
                    dedupeKey: "reward_completed:\\(rewardID)"
                )
                diagnostics.add("commerce", "rewarded_hint_granted")
                previewHint()
            case .unavailable:
                diagnostics.add("commerce", "rewarded_hint_unavailable")
                renderScene()
            case .notEarned:
                diagnostics.add("commerce", "rewarded_hint_not_earned")
                renderScene()
            case .failed:
                diagnostics.add("commerce", "rewarded_hint_failed")
                renderScene()
            }
        }
    }

    private func previewHint() {'''
if marker not in s:
    raise SystemExit('previewHint marker missing')
s = s.replace(marker, replacement, 1)

old_render = '        addFooter()\n    }'
new_render = '''        addFooter()
        if isRewardOfferVisible || isRewardRequestInFlight {
            addRewardedHintOffer()
        }
    }'''
if old_render not in s:
    raise SystemExit('render footer marker missing')
s = s.replace(old_render, new_render, 1)

footer_marker = '    private func addFooter() {'
reward_ui = '''    private func addRewardedHintOffer() {
        let blocker = SKShapeNode(rectOf: size)
        blocker.name = isRewardRequestInFlight ? nil : NodeName.rewardDecline
        blocker.position = CGPoint(x: size.width / 2, y: size.height / 2)
        blocker.fillColor = inkColor.withAlphaComponent(0.22)
        blocker.strokeColor = .clear
        blocker.zPosition = 90
        addChild(blocker)

        let card = SKShapeNode(
            rectOf: CGSize(width: min(320, size.width - 40), height: 190),
            cornerRadius: 28
        )
        card.position = CGPoint(x: size.width / 2, y: size.height / 2)
        card.fillColor = canvasColor
        card.strokeColor = inkColor.withAlphaComponent(0.12)
        card.lineWidth = 1
        card.zPosition = 91
        addChild(card)

        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.text = isRewardRequestInFlight ? "Opening reward…" : "Need a clue?"
        title.fontSize = 21
        title.fontColor = inkColor
        title.position = CGPoint(x: 0, y: 50)
        title.zPosition = 1
        card.addChild(title)

        let copy = SKLabelNode(fontNamed: "AvenirNext-Medium")
        copy.text = isRewardRequestInFlight
            ? "Your puzzle stays exactly as it is."
            : "Watch one optional rewarded ad to reveal a single hint."
        copy.fontSize = 13
        copy.fontColor = inkColor.withAlphaComponent(0.72)
        copy.position = CGPoint(x: 0, y: 18)
        copy.zPosition = 1
        card.addChild(copy)

        guard !isRewardRequestInFlight else { return }

        let accept = makeButton(
            title: "Watch & hint",
            name: NodeName.rewardAccept,
            width: 132
        )
        accept.position = CGPoint(x: -72, y: -48)
        accept.zPosition = 2
        card.addChild(accept)

        let decline = makeButton(
            title: "Not now",
            name: NodeName.rewardDecline,
            width: 112
        )
        decline.position = CGPoint(x: 72, y: -48)
        decline.zPosition = 2
        card.addChild(decline)
    }

'''
if footer_marker not in s:
    raise SystemExit('footer marker missing')
s = s.replace(footer_marker, reward_ui + footer_marker, 1)
p.write_text(s)

Path('NineTests/NineCommerceTests.swift').write_text('''import Testing
@testable import Nine

@Test func rewardedHintPolicyNeverMonetizesTeaching() {
    #expect(!NineRewardedHintPolicy.isEligible(isTutorial: true, isLevelComplete: false, hasActiveHint: false))
    #expect(!NineRewardedHintPolicy.isEligible(isTutorial: false, isLevelComplete: true, hasActiveHint: false))
    #expect(!NineRewardedHintPolicy.isEligible(isTutorial: false, isLevelComplete: false, hasActiveHint: true))
    #expect(NineRewardedHintPolicy.isEligible(isTutorial: false, isLevelComplete: false, hasActiveHint: false))
}
''')
