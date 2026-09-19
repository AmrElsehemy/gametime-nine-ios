# Nine analytics contract

Issue: #12

Nine instruments the smallest event set needed to understand onboarding, puzzle health, daily engagement, and later monetization. Analytics is observability only: tracking is synchronous, non-throwing at the game boundary, and must never block input, saving, progression, or offline play.

## Funnel

The launch funnel can be answered directly from these events:

1. `first_open`
2. `tutorial_started`
3. `tutorial_completed`
4. `level_completed` for the fifth tutorial level
5. later progression `level_completed` events

`first_open` is persisted locally and emitted once per install. Critical lifecycle events use explicit dedupe keys so scene callbacks or repeated calls cannot double-count the same logical event.

## Required event names

Gameplay and lifecycle:

- `first_open`
- `session_start`
- `session_end`
- `tutorial_started`
- `tutorial_completed`
- `level_started`
- `level_completed`
- `level_abandoned`
- `invalid_move`
- `undo`
- `reset`
- `hint`
- `daily_started`
- `daily_completed`

Commerce hooks are reserved now so the later commerce implementation does not invent an incompatible vocabulary:

- `reward_offer_shown`
- `reward_offer_accepted`
- `reward_completed`
- `iap_started`
- `iap_completed`

The commerce events are not emitted until the corresponding reward/IAP flows exist.

## Common dimensions

Events include only dimensions useful for product decisions:

- `app_version`
- `build_version`
- `level_id` when applicable
- `level_version` when applicable
- `board_size` when applicable
- `mode` (`progression` or `daily`) when applicable
- `duration_ms` as session-relative or level-relative elapsed time
- a small event-specific value such as `reason`, `day_key`, `hint_action`, or whether a level was restored

Raw board coordinates, free-form text, Game Center identity, device name, email, location, advertising identifiers, and replay contents are not analytics dimensions.

## Level health

A level can be diagnosed from the relationship between:

- starts
- completions
- abandons
- invalid moves
- hints
- resets
- undo usage
- solve duration

That is enough to identify suspicious difficulty spikes without recording every visual action or maintaining a server-authoritative session.

## Daily

Entering the daily mode emits `daily_started` alongside the level start. Solving it emits `daily_completed` alongside the level completion. The UTC day key is attached so daily retention can be grouped without storing personal time-zone or location information.

## Provider boundary

`NineAnalyticsClient` is injectable and intentionally tiny. The game currently uses a bounded debug client for local inspection; a production analytics SDK adapter can replace it without changing gameplay code or the event vocabulary.

The adapter contract does not throw into gameplay. Any SDK/network failure must be swallowed or buffered inside the adapter. Nine remains fully playable with a no-op analytics client.

## Debugging

`NineDebugAnalyticsClient` keeps a bounded event buffer and prints events in debug builds. This gives deterministic local inspection while the provider remains replaceable.

## Tests

Automated coverage verifies:

- the required launch and commerce event vocabulary exists
- `first_open` persists and is not duplicated
- critical dedupe keys suppress duplicate lifecycle events
- level events receive level/version/size/mode/duration dimensions
- board coordinates are not automatically included in analytics

## Future provider integration

When the production analytics provider is selected, prefer adapting the shared GameTime services layer rather than adding provider-specific calls throughout Nine. The event contract in this document remains the game-facing source of truth.
