# Progression, Persistence and Daily Challenge

Exactly One is local-first. Progress, active puzzle state, daily completion and streak state are stored locally and must remain usable with no network connection.

## Save schema

Current schema: **v2**.

`NineSaveState` stores:

- current progression level ID
- ordered unlocked level IDs
- per-level completion count and best completion duration
- the active puzzle session (mode, level ID, optional daily day key, marker positions)
- completed daily day keys mapped to bundled level IDs
- current/longest daily streak state

The codec explicitly probes `schemaVersion` before decoding. A synthetic v1 shape is migrated into v2 in tests. Unknown future schemas are rejected instead of being guessed.

The save is intentionally small enough for `UserDefaults`; game content itself stays in the bundled level pack.

## Corruption and catalog changes

On load, save data is sanitized against the current bundled catalog:

- unknown level IDs are discarded
- invalid marker coordinates are removed
- the first bundled level is always available as a recovery point
- a stale daily session is discarded when its UTC day has ended

If the saved JSON cannot be decoded, Exactly One removes that corrupt save payload and starts with fresh local progression. Tutorial completion and Sound/Haptics preferences already persist in their own small stores and are intentionally not duplicated into the progression payload.

## Progression

Completing a normal level:

1. records completion metadata and best time
2. unlocks the next bundled level
3. advances the persisted `currentLevelID`
4. clears the completed active session

Marker placements are saved as the active session while playing, so terminating and reopening the app returns to the same puzzle state.

## Daily challenge

Daily selection is deterministic and entirely offline:

- day identity uses the Gregorian calendar fixed to **UTC**
- onboarding levels are excluded
- a stable FNV-1a hash of `nine-daily-v1|YYYY-MM-DD` selects a bundled standard level
- Swift `hashValue` is never used because it is intentionally process-randomized
- a future remote config may provide an override **only for a bundled level ID**

This gives every install the same stable challenge for a given UTC day without requiring the backend.

A daily session captures its day key when it begins. If the clock crosses midnight while the puzzle is open, finishing it still credits the challenge day that was started rather than silently changing the puzzle's identity.

## Forgiving streak policy

Daily completion credit is idempotent per UTC day.

- first completed day starts streak at 1
- next UTC day increments by 1
- one missed day is forgiven: completing after a two-day gap preserves the current streak but does **not** inflate it
- a gap larger than one missed day resets current streak to 1
- same-day repeats do not add streak credit
- moving the clock backwards does not decrement or duplicate the streak
- longest streak is retained

Using UTC avoids destructive behavior when the device changes timezone while travelling.

## Development reset

`NineProgressStore.reset(levels:)` clears only the progression save and returns a fresh state. It is suitable for development/test reset tooling without deleting unrelated app preferences.

## Future backend integration

The backend is optional. A future daily override or disabled-level list may influence selection, but the client must always have a valid bundled/default path and must never require a network response to resume progress or play normal puzzles.
