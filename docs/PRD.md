# Game #001 — Nine PRD

## Status
Internal codename: **Nine**  
Public product name: **TBD after the visual/brand pass**  
Platform: iOS  
Studio: Knowlly Games  
Internal platform: Game Time  
Release target: App Store submission by Day 10

## 1. Purpose
Nine is the first public Game Time title and the first production proof of the Knowlly Games studio pipeline.

The mechanic is intentionally simple so engineering effort can validate the reusable horizontal systems: native rendering, onboarding, haptics/audio, persistence, replay, analytics, diagnostics, Game Center, rewarded monetization, StoreKit where justified, TestFlight/App Store release, support, visual/asset production, and marketing capture.

## 2. Player promise
A polished logic puzzle that can be understood by playing, solved in short sessions, and mastered through increasingly challenging boards.

The player should:
- interact within roughly 3 seconds of launch
- understand the basic mechanic within the first minute
- experience an early win quickly
- never need a manual before playing
- be able to play core content offline

## 3. Core mechanic
The board is divided into rows, columns, and colored/visual regions.

The player places or removes markers on cells while satisfying constraints.

Initial rule family:
- exactly one marker per row
- exactly one marker per column
- exactly one marker per region
- markers may not touch where adjacency rules apply

The exact final rule set may be tuned during implementation, but it must stay easy to explain through interaction and deterministic to validate.

Every ordinary shipped production puzzle must have **exactly one valid solution**. Ambiguous/multi-solution boards are rejected by the content pipeline.

## 4. Core loop
1. Open a level.
2. Tap cells to place/remove markers.
3. Show immediate feedback for valid/invalid/conflicting state.
4. Player reasons and iterates.
5. Board satisfies all constraints.
6. Trigger satisfying completion sequence.
7. Persist progress/reward.
8. Continue to next level or daily challenge.

## 5. Visual product direction
Visual identity is part of Game #001, not post-code polish.

Initial direction:
- avoid generic chess/queen/crown presentation
- use a tactile, premium, playful board language
- irregular regions should read clearly without relying only on color
- marker/piece design should be ownable enough to support an app icon and marketing identity
- semantic motion should make placement, conflict, hint, solve and milestones feel distinct
- solved states should create visually satisfying capture moments
- art direction must produce assets usable in-game, App Store screenshots, website and social creative

The current production-capable fallback is **Tactile Territories**: a procedural SpriteKit/Core Graphics visual system with material-like territories and a distinctive Pebble marker. Bespoke illustration must not become a release blocker.

The public product name should be locked only after the visual system is strong enough to judge the name in context.

## 6. Onboarding
The first levels are the tutorial.

### Level 1
- extremely small/easy
- one obvious interaction
- animated hint only after brief hesitation
- completion within seconds

### Level 2
- reinforce placement
- introduce row/column uniqueness

### Level 3
- introduce region uniqueness

### Level 4
- introduce adjacency restriction

### Level 5
- full ordinary rules with minimal guidance

Assistance escalates only when the player hesitates or repeatedly makes invalid moves. Initial tunable thresholds are defined in the onboarding implementation issue.

No monetization is shown during the initial teaching flow.

## 7. v1 scope
- portrait iPhone-first presentation
- deterministic board/rule engine independent of SpriteKit
- complete visual identity + art asset system
- tap-to-place/remove
- invalid/conflict feedback
- undo
- reset
- hint
- timer where useful
- level progression
- local save with versioned schema
- **submission hard floor of 60 unique, solver-verified puzzles**
- target 100+ validated/curated puzzles when quality and difficulty curation support it
- daily challenge
- forgiving streak
- haptics
- sound
- semantic completion/celebration FX
- analytics
- replay event logging
- crash/non-fatal diagnostics
- Game Center leaderboard/achievements where useful
- rewarded ad for optional value such as a hint or bonus reward
- settings, support and privacy links
- StoreKit only for products that provide a real player-facing entitlement/value
- accessibility basics
- App Store icon/screenshots/preview assets
- marketing capture hooks and initial social creatives

## 8. Content validation and solver
The production content pipeline must distinguish:
- `0` solutions → invalid
- `1` solution → valid production puzzle
- `2+` solutions → ambiguous and rejected for ordinary shipped content

The v1 solver uses deterministic backtracking with:
- MRV (minimum remaining values)
- forward checking
- immediate pruning for row/column/region/adjacency conflicts
- deterministic candidate ordering
- bounded solution counting that stops after the second solution

This approach is intentionally chosen over Algorithm X/DLX for v1 because the small 6×6–9×9 boards and adjacency constraint are naturally handled by incremental backtracking without added exact-cover machinery.

Solver work metrics such as visited nodes, branches and backtracks may contribute to difficulty estimation but are not the sole difficulty measure.

## 9. Monetization
Primary model: rewarded value.

Initial opportunities:
- watch a rewarded ad for a free hint
- optionally double an earned reward after completion when there is meaningful reward value to double

Initial provider: **Google AdMob / Google Mobile Ads SDK**, isolated behind `GameTimeCommerce`.

Rules:
- rewarded ads only initially
- no mediation in v1
- the full game remains playable without ads
- no monetization during first-time teaching flow
- no interstitial during active gameplay
- no artificial failures designed to force monetization
- ad failure never blocks play

### Remove Ads decision
Do **not** ship a `Remove Ads` IAP merely because optional rewarded ads exist. If a later v1 decision introduces a real non-rewarded placement, then a clearly defined Remove Ads entitlement may be added and must be restorable. Otherwise the product is omitted.

Coins may be introduced only if they improve the loop without bloating v1.

## 10. Progression and retention
v1 should support:
- sequential level progression
- daily puzzle
- streak tracking
- personal best time where meaningful
- Game Center leaderboard for daily/score/time where meaningful

Premium pass, large store, events, cosmetics and advanced LiveOps are post-v1 unless retention proves demand.

## 11. Rendering and technology
- Swift
- SpriteKit for the game surface and effects
- UIKit/Core Animation only where cleaner for shell UI
- Core Haptics
- AVFoundation
- GameKit
- StoreKit 2 where an actual product requires it

The rule engine and solver must not depend on SpriteKit.

## 12. Replay
Record enough deterministic information to reproduce a session:
- app/game version
- level version/id
- seed if used
- player input events
- relevant state transitions

Replay supports QA, bug reproduction, analytics, and later automated marketing capture.

## 13. Analytics
Minimum events:
- first_open
- tutorial_started
- tutorial_completed
- level_started
- level_completed
- level_failed/abandoned where meaningful
- invalid_move
- undo_used
- hint_used
- reset_used
- daily_started
- daily_completed
- reward_offer_shown
- reward_offer_accepted
- reward_completed
- iap_started/iap_completed only if an IAP ships
- session_start/session_end

All analytics must avoid collecting unnecessary personal information.

## 14. Quality bar
Before submission:
- all v1 rules covered by unit tests
- every ordinary shipped production level has exactly one solver-verified solution
- production content meets the submission hard floor
- persisted-state migration tested
- no P0/P1 known defects
- onboarding verified from clean install
- offline play verified
- ad failure does not block play
- Game Center failure does not block play
- any shipped purchase entitlement/restore flow verified in sandbox
- replay reproduces representative sessions
- acceptable performance on supported devices
- final visual identity is coherent across gameplay, app icon, App Store and web/social surfaces
- release build is validated against the real GameTimeKit dependency rather than only a CI contract stub
- live support/privacy URLs match the actual shipped SDK/data behavior

## 15. Out of scope
- custom username/password accounts
- multiplayer
- premium/season pass
- giant store
- cross-game identity/XP
- generic level editor
- sophisticated backend dependency
- server-authoritative gameplay

## 16. Definition of done
Game #001 v1.0 is done when it is submitted to App Review with production-ready gameplay, visual identity/assets, onboarding, telemetry, justified monetization, support/privacy surfaces, App Store assets, launch creatives, and a tested release build.

A framework build or TestFlight-only state is not considered shipped.
