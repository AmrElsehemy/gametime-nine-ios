# Nine deterministic replay, diagnostics, and support payload

Issue: #11

## Purpose

Nine records **player intent**, not rendered frames. A replay is a small, versioned, deterministic description of the logical session that can be used for regression tests, support reproduction, QA, and later marketing capture.

Replay and diagnostics are never required for core play. Failure to encode, export, import, or inspect diagnostic data must not block puzzle interaction.

## Replay schema v1

`NineReplay.currentSchemaVersion == 1`.

A replay contains:

- replay schema version
- replay UUID
- app version and build version
- level ID and level schema version
- play mode (`progression` or `daily`)
- optional daily day key
- exact initial marker coordinates
- ordered semantic input events

Each event contains:

- monotonically increasing `sequence`
- semantic `kind`
- optional board coordinate

Supported event kinds in v1:

- `place`
- `remove`
- `undo`
- `reset`
- `hint_preview`

The replay deliberately does **not** serialize SpriteKit nodes, animation timing, audio state, haptic state, or frame-by-frame rendering.

## Determinism contract

`NineReplayPlayer` reconstructs a board from the replay's initial markers and applies each intent through the same logical board mutations used by gameplay.

A valid completed session must reproduce the same final `NineBoardState.markers` when replayed against the same compatible level definition.

Compatibility is explicit. Playback rejects:

- unsupported replay schema versions
- a replay whose level ID does not match the requested level
- a replay whose level schema version does not match
- malformed or out-of-order event sequences
- impossible place/remove/undo operations

These cases throw `NineReplayError`; they are diagnostic failures, not gameplay failures.

## Recording lifecycle

A fresh recorder starts whenever a level is loaded. The recorder captures the exact logical starting markers, including a restored in-progress session when applicable.

Gameplay intents are appended after successful logical mutations. Hint preview is recorded even though it intentionally does not mutate the board. On completion, the finished replay is retained as the most recent completed replay for support/debug packaging.

## Development import/export

Debug builds provide local replay encode/decode helpers using `NineReplayCodec` and JSON.

The format is intentionally plain and diffable so a captured replay can become a regression fixture. Production UI does not expose arbitrary replay import.

## Diagnostics breadcrumbs

`NineDiagnosticsBuffer` is an in-memory bounded ring-style buffer. It currently records small semantic breadcrumbs such as:

- level loaded/completed
- save restored/persisted
- replay imported/exported
- validation conflicts where useful

Breadcrumbs must stay terse and must not contain chat text, contacts, account identifiers, free-form user content, or advertising identifiers.

The buffer is intentionally local and non-throwing. Diagnostic recording is observability, never a gameplay dependency.

## Support package

`NineSupportPackage` is versioned separately and contains only the minimum technical context needed to reproduce a problem:

- app version
- build version
- coarse device class (`iPhone` / `iPad`)
- coarse OS class/version
- level ID and level schema version
- current or most recently completed replay, including its replay ID
- bounded recent diagnostic breadcrumbs

It intentionally does not include player name, email, device name, contacts, location, Game Center identity, advertising identifiers, or arbitrary user-authored text.

A future Report Problem surface must require an explicit user action before a support package leaves the device.

## Testing

Automated tests cover:

1. replay encode/decode round trip
2. representative place/undo/place/hint-preview session reproducing the same final logical board state
3. compatibility failure for unsupported schema versions
4. malformed sequence rejection
5. bounded diagnostic retention
6. support-payload encode/decode and absence of personal-data fields by construction

Replay fixtures should grow when production bugs expose new deterministic failure modes.

## Future extensions

Only add fields when required by a game mechanic. Potential examples are deterministic RNG seed, physics snapshots, economy transaction IDs, or remote level content version. New semantics require a replay schema version bump or backwards-compatible decoding path.
