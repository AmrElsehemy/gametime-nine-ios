# Exactly One Content Factory

Exactly One uses a deterministic **sidecar CLI**, not a second GUI app, for v1 content production.

## Why a CLI first

The product bottleneck is high-quality validated puzzle inventory, not editor UX. A separate visual authoring app would create another product to design, test and maintain before Game #001 ships. The CLI keeps the loop fast and reproducible while preserving the option to add a visual inspector later if human curation becomes the bottleneck.

## Command

```bash
python3 Tools/level_factory.py --write ExactlyOne/Resources/ExactlyOneLevels-v1.json
python3 Tools/level_factory.py --check ExactlyOne/Resources/ExactlyOneLevels-v1.json
```

`--write` regenerates the complete pack. `--check` fails if the checked-in JSON does not exactly match deterministic factory output.

CI runs `--check` on every pull request (`.github/workflows/level-pack.yml`), so a hand edit to the pack fails until the factory produces the same output.

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
9. attaching Focus Clock thresholds (`focusTuning`) computed from board size and difficulty. The formula mirrors `ExactlyOneFocusTuning.initial(size:difficulty:)`, so change both together.

The generated portfolio intentionally spans 6×6 through 9×9. The checked-in pack is the shipping artifact; generation is never performed on the player device.

## Chapter 2 (1.1)

Chapter 2 is generated after Chapter 1 from its own seed (`CHAPTER_TWO_SEED`), so the original 100 records stay byte-identical. It keeps the same pipeline with tighter limits:

- only 8×8 (25 levels) and 9×9 (35 levels) boards;
- at most one starting pebble, where Chapter 1's large boards usually start with two, so each board has a longer deduction chain;
- ids `v2-001` ... `v2-060`, orders 101–160, `"chapter": 2`;
- difficulty 4 for the first half and 5 for the rest, which feeds the Focus Clock thresholds.

Chapter 2 opens at **180★** earned in Chapter 1 (of 300 possible), set in `CHAPTERS`. That's about two stars a puzzle, so a one-star run through Chapter 1 has to go back and replay. Retune it from `chapter_unlocked` data rather than guessing.

Generating Chapter 2 takes about 40 seconds, most of it rejecting 9×9 boards that need more than one starting pebble to be unique.

## Trust boundary

The Python solver is an authoring filter only. The Swift `ExactlyOneLevelPackValidator` remains the shipping source of truth and re-solves every bundled level in CI. A generated level cannot ship merely because the sidecar accepts it.

Every production level must therefore satisfy both independent implementations:

- valid schema and region topology data;
- authored solution satisfies all active rules;
- exactly one solution under the shipped clues;
- deterministic solver result;
- unique id/order and valid difficulty metadata.

## Current content gate

The pack contains **160 solver-verified levels** (Chapter 1: 100, Chapter 2: 60), satisfying the Day-3 (20), TestFlight (50), App Store submission (60), and v1 target (100) count gates.

Count is not the same thing as quality. Cold-start onboarding validation and representative human difficulty/play-quality sampling remain release QA responsibilities.

## Future evolution

Do not build a graphical level editor by default. Add a lightweight visual inspector only when one of these becomes true:

- human review of generated boards is slower than generation itself;
- difficulty curation needs side-by-side visual comparison;
- designers need manual territory edits often enough to justify tooling;
- multiple Game Time titles can reuse the inspector architecture.

At that point the natural next step is a macOS/SwiftUI internal inspector that consumes the exact same JSON schema and Swift validator, not a parallel content format.
