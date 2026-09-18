# Game #001 Local Development

## Checkout layout

Game #001 uses the shared GameTimeKit as a local Swift package during active development.

Keep both repositories as siblings:

```text
~/Work/GameTime/
├── gametime-ios/
└── gametime-nine-ios/
```

The Xcode project references `../gametime-ios` through `XCLocalSwiftPackageReference`.

## Open and run

1. Clone both repositories into the sibling layout above.
2. Open `Nine.xcodeproj`.
3. Select the `Nine` scheme.
4. Choose an iPhone simulator or device.
5. Build and run.

The first bootstrap screen is intentionally minimal: it proves the app target, SpriteKit surface and GameTimeKit dependency are connected. Gameplay rules are implemented by subsequent issues.

## Release package policy

Local package linkage is for active development. Before public release, GameTimeKit should be tagged and the app should pin a known-good package version.
