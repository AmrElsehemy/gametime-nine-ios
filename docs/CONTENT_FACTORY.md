# Nine Content Factory

Nine uses a deterministic **sidecar CLI**, not a second GUI app, for v1 content production.

## Why a CLI first

The product bottleneck is high-quality validated puzzle inventory, not editor UX. A separate visual authoring app would create another product to design, test and maintain before Game #001 ships. The CLI keeps the loop fast and reproducible while preserving the option to add a visual inspector later if human curation becomes the bottleneck.

## Command

```bash
python3 Tools/level_factory.py --write Nine/Resources/NineLevels-v1.json
python3 Tools/level_factory.py --check Nine/Resources/NineLevels-v1.json
```

`--write` regenerates the complete v1 pack. `--check` fails if the checked-in JSON does not exactly match deterministic factory output.

## v1 generation strategy

The first five onboarding puzzles remain hand-curated. The factory generates the remaining 95 puzzles by:

1. growing deterministic four-connected territory maps from an `authoringSeed`;
2. solving the board with an independent bounded constraint solver;
3. rejecting unsolvable candidates;
4. accepting immediately unique boards with no authored clue;
5. for larger boards, adding the minimum solution clue count (up to the configured bound) needed to make the board unique;
6. rejecting any candidate that still has multiple solutions;
7. ordering accepted puzzles by board size and a difficulty signal that combines solver work, branching, board size and clue burden;
8. writing stable ids `v1-001` ... `v1-100`.

The generated portfolio intentionally spans 6×6 through 9×9. The checked-in pack is the shipping artifact; generation is never performed on the player device.

## Trust boundary

The Python solver is an authoring filter only. The Swift `NineLevelPackValidator` remains the shipping source of truth and re-solves every bundled level in CI. A generated level cannot ship merely because the sidecar accepts it.

Every production level must therefore satisfy both independent implementations:

- valid schema and region topology data;
- authored solution satisfies all active rules;
- exactly one solution under the shipped clues;
- deterministic solver result;
- unique id/order and valid difficulty metadata.

## Current content gate

The v1 pack contains **100 solver-verified levels**, satisfying the Day-3 (20), TestFlight (50), App Store submission (60), and v1 target (100) count gates.

Count is not the same thing as quality. Cold-start onboarding validation and representative human difficulty/play-quality sampling remain release QA responsibilities.

## Future evolution

Do not build a graphical level editor by default. Add a lightweight visual inspector only when one of these becomes true:

- human review of generated boards is slower than generation itself;
- difficulty curation needs side-by-side visual comparison;
- designers need manual territory edits often enough to justify tooling;
- multiple Game Time titles can reuse the inspector architecture.

At that point the natural next step is a macOS/SwiftUI internal inspector that consumes the exact same JSON schema and Swift validator, not a parallel content format.
