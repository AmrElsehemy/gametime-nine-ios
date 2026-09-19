# Undo, Reset and Hints

Nine gives players recovery and assistance tools without coupling puzzle rules to monetization or advertising.

## Undo

Undo is logical-state based, not animation based.

- every successful player placement/removal records the resulting marker set
- Undo restores the immediately previous marker set and re-evaluates constraints
- repeated Undo walks backward until the state that was loaded/reset
- Undo never crosses a level load, mode switch, or app relaunch in v1
- an undo result is persisted as the current active session
- pressing Undo when no previous state exists is a no-op

The history primitive is framework-independent (`NineMoveHistory`) and can later move into a shared puzzle module if another Game Time title proves the reuse.

## Reset

Reset always restores the exact authored `initialMarkers` for the current bundled level, clears transient hint/history state, restarts the level timer, persists the restored board, and emits a semantic reset intent.

## Hint model

Hints are **preview-first**. Asking for a hint never mutates the board.

`NineHintEngine` follows deterministic priority:

1. if a player-added marker is currently conflicting, preview removing the deterministic first conflict
2. otherwise if a player-added marker is not part of the level's unique authored solution, preview removing it
3. otherwise preview the first missing coordinate from the unique authored solution

Because production levels are required to have exactly one solver-verified solution, the hint engine never has to choose arbitrarily between valid solutions.

A hint renders both:

- a ring around the target cell
- an explicit `+` or `−` cue and text telling the player to place or remove

The board changes only when the player performs that action.

## Tutorial and monetization boundary

Hints are usable without an ad dependency. The initial tutorial already supplies adaptive free guidance; no ad or purchase is required to learn the game.

Later, `GameTimeCommerce` may decide whether a non-tutorial hint preview is free, earned, or optionally unlocked by a rewarded ad. That eligibility decision must happen outside `NineHintEngine`; the engine itself only answers the puzzle question.

## Replay / analytics seam

Gameplay currently emits a small semantic intent vocabulary:

- `place`
- `remove`
- `undo`
- `reset`
- `hint_preview`

The in-memory buffer is intentionally lightweight. Issue #11 will turn the same semantic events into the versioned deterministic replay format; issue #12 will route the appropriate subset into provider-agnostic analytics.

## Failure behavior

Undo/hint state is never required to load or solve a puzzle. If feedback, analytics, ads, or future replay storage fail, logical gameplay remains usable and offline-first.
