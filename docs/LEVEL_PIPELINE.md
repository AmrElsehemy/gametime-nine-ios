# Exactly One Level Pipeline

Exactly One's production puzzle content is data, not game logic.

## Source of truth

The first production pack is `Nine/Resources/NineLevels-v1.json`.

Each record contains:
- stable `id`
- deterministic `order`
- `kind` (`onboarding` or `standard`)
- board `size`
- row-major `regionIDs`
- enabled `adjacencyRule`
- optional `initialMarkers`
- authored `solution`
- inspectable `difficulty` (1...5)
- optional `authoringSeed`

The pack itself has a schema version. Unsupported pack versions fail validation rather than being interpreted optimistically.

## Solver contract

`NineLevelSolver` is framework-independent and deterministic. It uses:
1. one placement domain per unresolved row
2. MRV (minimum remaining values) to pick the next row
3. deterministic ascending candidate order
4. immediate row/column/region/adjacency pruning
5. forward checking after each placement
6. bounded solution counting that stops after the second solution

The solver reports `none`, `unique`, or `2+` and exposes visited-node, backtrack, and max-branching metrics as difficulty signals.

## Shipping rule

Every normal production level must have **exactly one solution**. The validator also checks that:
- IDs and orders are unique
- difficulty is in range
- initial markers are part of the authored solution
- the authored solution actually solves the board
- deterministic solver output matches the authored solution

CI must reject a pack containing an impossible or ambiguous level.

## Content gates

- Day 3: 20 validated levels
- TestFlight: 50 validated levels
- App Store submission: 60 validated levels
- v1 target: 100+ when quality supports it

`NineContentGate` makes these thresholds machine-checkable. The first checked-in pack deliberately satisfies only the Day-3 gate; later packs must grow before TestFlight/submission.

## Adding or changing a level

1. Edit or generate a record in the JSON pack. Do not change SpriteKit/game-rule code.
2. Give the level a stable ID and unique order.
3. Provide the intended solution and any onboarding clues.
4. Run the test suite.
5. The full pack is decoded and solver-validated. Any `0` or `2+` solution level fails.
6. Inspect solver metrics plus actual playtest behavior before changing the authored difficulty label.
7. For onboarding levels, keep ordering explicit and coordinate changes with the learn-by-playing flow.

A graphical editor is intentionally not part of v1. If level authoring becomes a demonstrated bottleneck, build tooling against this same versioned schema rather than inventing a second content format.
