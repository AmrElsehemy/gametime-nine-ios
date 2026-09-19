# Exactly One — Game Time Game #001

**Public product name:** Exactly One  
**App Store title:** Exactly One: Logic Puzzle  
**Internal codename:** Nine  
**Studio:** Knowlly Games  
**Platform:** native iOS

Exactly One is Game Time Game #001: a polished constraint-placement logic puzzle used to prove the full Knowlly Games pipeline from idea → build → TestFlight → App Store → marketing → learning.

The player places exactly one pebble in every row, column, and territory. No two pebbles may touch.

This repository owns everything specific to Game #001: app target, rules, levels, art/assets, visual identity, onboarding, game-specific tests, App Store assets, marketing capture configuration, and release work.

Shared platform code belongs in [`AmrElsehemy/gametime-ios`](https://github.com/AmrElsehemy/gametime-ios) and is consumed as GameTimeKit. Shared control-plane work belongs in `gametime-backend`; public marketing/support/legal web work belongs in `gametime-web`.

## Naming

- **Exactly One** is the public product name.
- **Exactly One: Logic Puzzle** is the App Store title.
- **One pebble. Every territory.** is the App Store subtitle.
- **Nine** remains the internal engineering codename for the repository, Xcode project, targets, schemes, modules, and internal identifiers unless a technical migration is explicitly approved.
- Public-facing UI, metadata, screenshots, website copy, support copy, and marketing must use **Exactly One**, never **Nine**.

See [`docs/BRAND.md`](docs/BRAND.md) for the canonical naming and messaging decision.

## Product rules

- Visual identity and asset production are first-class product work, not polish added at the end.
- Native Apple stack: Swift + SpriteKit, with Core Haptics, AVFoundation, GameKit and StoreKit 2.
- Core gameplay works offline.
- No proprietary login in v1.
- Game rules remain independent of SpriteKit rendering.
- Learn by playing; no tutorial wall.
- Rewarded monetization adds optional value, never manufactured frustration.
- Public App Store submission is the definition of done.

## Build and run

Keep the game repo and shared platform repo as siblings:

```text
~/Work/GameTime/
├── gametime-ios/
└── gametime-nine-ios/
```

Then open `Nine.xcodeproj`, select the `Nine` scheme, and run on an iPhone simulator/device. The project consumes `../gametime-ios` as a local Swift package during active development.

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) for the full local-development/package workflow.

## Documentation

Start with [`docs/PRD.md`](docs/PRD.md). The public naming and messaging contract is recorded in [`docs/BRAND.md`](docs/BRAND.md).
