# Game #001 Assets

This directory owns **game-specific** visual/audio assets. Shared reusable experience code belongs in `gametime-ios`; Nine-specific identity stays here.

## Planned structure

```text
Assets/
├── AppIcon/
├── Board/
├── Pieces/
├── FX/
├── Audio/
└── Reference/
```

Do not commit licensed third-party assets unless their redistribution/use terms are documented.

## Production preference

Prefer procedural/native assets where they improve iteration speed and scaling:
- region shapes and fills: SpriteKit/Core Graphics
- token silhouette/material: vector/procedural first
- glows/rings/conflict indicators: SpriteKit/Core Animation
- particles: SpriteKit particle systems

Raster assets should be reserved for visuals that materially benefit from them.

## Naming convention

Use semantic names, not screen-coordinate names.

Examples:
- `token_pebble_base`
- `token_pebble_highlight`
- `fx_conflict_ring`
- `fx_hint_ghost`
- `sfx_place_01`
- `sfx_conflict_01`
- `sfx_solve_01`

## Required v1 outputs

- production token/piece system
- region visual treatment
- conflict/hint/selection states
- solve FX
- app icon master
- App Store screenshot-ready game state
- clean gameplay-capture state

See `docs/ART_DIRECTION.md` for the selected visual direction.
