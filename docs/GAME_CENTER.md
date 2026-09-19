# Nine Game Center

Issue: #13

Nine uses Apple's native Game Center layer for optional identity, achievements, and daily competition. Game Center is an enhancement only: authentication failure, cancellation, network failure, score submission failure, or achievement-reporting failure must never block puzzle play, saves, progression, daily selection, or completion.

## Product contract

- Authentication is requested opportunistically after the game scene becomes active.
- Declining or failing authentication leaves Nine fully playable.
- Authenticated players get the native Game Center access point.
- Daily results use solve duration in **milliseconds**; lower is better.
- Game Center errors become diagnostic breadcrumbs only.
- Nine does not create a proprietary account system.

## Identifiers

Use these stable identifiers in code and App Store Connect:

### Leaderboard

`ai.knowlly.nine.daily.time`

Configuration intent:

- score format: integer
- unit: milliseconds
- sort order: low to high
- recurring: daily
- score range: 1 ... 86,400,000

A recurring daily leaderboard gives each daily puzzle a fresh competitive surface while Nine keeps using the same stable identifier.

### Achievements

| Identifier | Meaning | Percent |
| --- | --- | ---: |
| `ai.knowlly.nine.achievement.first-solve` | Solve any puzzle | 100 |
| `ai.knowlly.nine.achievement.tutorial-complete` | Complete the five-level learn-by-playing sequence | 100 |
| `ai.knowlly.nine.achievement.first-daily` | Complete a daily puzzle | 100 |
| `ai.knowlly.nine.achievement.streak-7` | Reach a seven-day daily streak | 100 |

The first set is deliberately small and meaningful. Do not add filler achievements simply to increase count.

## Duplicate safety

The Game Center service maintains a local completed/reported set for the running session and hydrates it from Game Center after successful authentication. Reporting a completed achievement twice in one session is suppressed. A failed report is removed from the local set so a later attempt can retry.

Game Center remains the authority for cross-device achievement state.

## Daily score validity

Nine submits only after the local deterministic puzzle engine has marked the daily puzzle solved. The score is derived from the same monotonic elapsed duration used by local completion tracking:

`milliseconds = max(1, round(durationSeconds * 1000))`

No score is submitted for abandoned, reset, or unsolved sessions.

This is client-authoritative for v1. If leaderboard abuse becomes material later, add server verification rather than making the v1 game online-dependent.

## Native access UI

When authenticated, `GKAccessPoint` is enabled so players can open the native Game Center surface without Nine building a parallel profile/social UI. It is disabled when the player is not authenticated.

## App Store Connect checklist

Before sandbox verification:

- [ ] Enable the Game Center capability for the Nine App ID / Xcode target.
- [ ] Confirm the app's bundle identifier is the production Nine bundle identifier.
- [ ] Enable Game Center for the app record in App Store Connect.
- [ ] Create leaderboard `ai.knowlly.nine.daily.time` with low-to-high ordering and daily recurrence.
- [ ] Create the four achievement identifiers exactly as documented above.
- [ ] Add localized leaderboard/achievement names and descriptions.
- [ ] Add achievement artwork that matches the final Nine visual language.
- [ ] Confirm sandbox tester / Game Center test account access.
- [ ] Run on a signed physical device or suitable signed sandbox build.
- [ ] Verify auth decline/cancel still leaves the game playable.
- [ ] Verify a daily solve submits a millisecond score.
- [ ] Verify completing an achievement reports once and repeated reporting is harmless.
- [ ] Verify Game Center network/account failure is non-blocking.

The Apple-side configuration and signed sandbox run are human/account gates; code completion alone does not satisfy those two checks.

## Test strategy

Automated tests cover pure policy that does not need Apple's live service:

- duration-to-millisecond score conversion
- zero/negative duration clamping
- achievement duplicate suppression
- failed-report retry policy
- stable identifiers

Live authentication and actual sandbox leaderboard/achievement delivery require App Store Connect configuration and a signed Game Center environment.
