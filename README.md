# Game Time — Nine (Game #001)

**Internal codename:** Nine  
**Public name:** TBD after the visual/brand pass  
**Studio:** Knowlly Games  
**Platform:** native iOS

Nine is Game Time Game #001: a polished constraint-placement logic puzzle used to prove the full Knowlly Games pipeline from idea → build → TestFlight → App Store → marketing → learning.

This repository owns everything specific to Game #001: app target, rules, levels, art/assets, visual identity, onboarding, game-specific tests, App Store assets, marketing capture configuration, and release work.

Shared platform code belongs in [`AmrElsehemy/gametime-ios`](https://github.com/AmrElsehemy/gametime-ios) and is consumed as GameTimeKit. Shared control-plane work belongs in `gametime-backend`; public marketing/support/legal web work belongs in `gametime-web`.

## Product rules

- Nine is an **internal codename**, not yet the final App Store name.
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

Start with [`docs/PRD.md`](docs/PRD.md). Visual identity work is tracked separately and should merge into this repo once the production direction is proven.
