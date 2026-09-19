#!/usr/bin/env python3
"""Deterministic sidecar content factory for Nine.

This is intentionally a CLI, not a second product/UI. It generates candidate connected
territory maps, solves them independently, adds the minimum authored clue count needed
for uniqueness, sorts accepted puzzles into a progression, and writes the production
JSON pack. The Swift validator remains the shipping source of truth in CI.
"""

from __future__ import annotations

import argparse
import itertools
import json
import random
from pathlib import Path

SCHEMA_VERSION = 1
BASE_SEED = 2_026_091_901
TARGET_COUNT = 100

# The first five puzzles remain deliberately hand-curated because they teach the game.
ONBOARDING = [
    {"id":"v1-001","order":1,"kind":"onboarding","size":6,"regionIDs":[1,0,0,0,0,0,1,1,1,0,0,0,2,1,1,0,0,0,2,4,5,3,0,3,2,4,5,3,3,3,4,4,5,5,3,3],"adjacencyRule":"noTouching","initialMarkers":[{"row":0,"column":4},{"row":1,"column":2},{"row":2,"column":0},{"row":3,"column":5},{"row":4,"column":1}],"solution":[{"row":0,"column":4},{"row":1,"column":2},{"row":2,"column":0},{"row":3,"column":5},{"row":4,"column":1},{"row":5,"column":3}],"difficulty":1,"authoringSeed":2273},
    {"id":"v1-002","order":2,"kind":"onboarding","size":6,"regionIDs":[1,1,1,0,0,0,1,1,2,2,0,0,1,1,2,2,2,0,4,4,3,3,2,2,4,3,3,5,2,2,4,4,3,5,2,2],"adjacencyRule":"noTouching","initialMarkers":[{"row":0,"column":5},{"row":1,"column":1},{"row":2,"column":4}],"solution":[{"row":0,"column":5},{"row":1,"column":1},{"row":2,"column":4},{"row":3,"column":2},{"row":4,"column":0},{"row":5,"column":3}],"difficulty":1,"authoringSeed":2339},
    {"id":"v1-003","order":3,"kind":"onboarding","size":6,"regionIDs":[2,2,1,1,0,0,2,2,3,1,1,1,2,2,3,1,1,1,2,2,3,3,3,3,2,3,3,3,4,4,5,5,5,5,4,4],"adjacencyRule":"noTouching","initialMarkers":[{"row":0,"column":5},{"row":1,"column":3}],"solution":[{"row":0,"column":5},{"row":1,"column":3},{"row":2,"column":0},{"row":3,"column":2},{"row":4,"column":4},{"row":5,"column":1}],"difficulty":1,"authoringSeed":3497},
    {"id":"v1-004","order":4,"kind":"onboarding","size":6,"regionIDs":[0,0,0,0,2,2,0,1,1,1,1,2,4,4,1,3,5,2,4,4,4,3,5,2,4,4,4,5,5,5,4,4,5,5,5,5],"adjacencyRule":"noTouching","initialMarkers":[{"row":0,"column":0}],"solution":[{"row":0,"column":0},{"row":1,"column":2},{"row":2,"column":5},{"row":3,"column":3},{"row":4,"column":1},{"row":5,"column":4}],"difficulty":1,"authoringSeed":3557},
    {"id":"v1-005","order":5,"kind":"onboarding","size":6,"regionIDs":[1,1,0,0,2,2,1,1,1,1,2,2,4,4,4,2,2,2,4,4,4,3,3,2,4,4,4,5,5,5,4,4,4,5,5,5],"adjacencyRule":"noTouching","initialMarkers":[],"solution":[{"row":0,"column":2},{"row":1,"column":0},{"row":2,"column":5},{"row":3,"column":3},{"row":4,"column":1},{"row":5,"column":4}],"difficulty":2,"authoringSeed":3633},
]


def connected_partition(size: int, seed: int) -> tuple[int, ...]:
    """Grow exactly `size` four-connected territories from deterministic random seeds."""
    rng = random.Random(seed)
    cells = [(r, c) for r in range(size) for c in range(size)]
    seeds = rng.sample(cells, size)
    grid = [[-1] * size for _ in range(size)]
    frontiers = [set() for _ in range(size)]
    territory_sizes = [0] * size
    directions = ((-1, 0), (1, 0), (0, -1), (0, 1))

    def expose(row: int, column: int, territory: int) -> None:
        for dr, dc in directions:
            rr, cc = row + dr, column + dc
            if 0 <= rr < size and 0 <= cc < size and grid[rr][cc] < 0:
                frontiers[territory].add((rr, cc))

    for territory, (row, column) in enumerate(seeds):
        grid[row][column] = territory
        territory_sizes[territory] = 1
    for territory, (row, column) in enumerate(seeds):
        expose(row, column, territory)

    remaining = size * size - size
    while remaining:
        candidates = [i for i in range(size) if frontiers[i]]
        if not candidates:
            raise RuntimeError("territory growth stalled")

        # Prefer smaller territories without forcing uniform shapes.
        weights = [1.0 / (territory_sizes[i] + 0.7) for i in candidates]
        territory = rng.choices(candidates, weights=weights, k=1)[0]
        row, column = rng.choice(tuple(sorted(frontiers[territory])))
        grid[row][column] = territory
        territory_sizes[territory] += 1
        remaining -= 1

        for frontier in frontiers:
            frontier.discard((row, column))
        expose(row, column, territory)

    return tuple(cell for row in grid for cell in row)


def solve(
    size: int,
    regions: tuple[int, ...],
    clues: tuple[tuple[int, int], ...] = (),
    limit: int = 2,
) -> tuple[list[tuple[int, ...]], tuple[int, int, int]]:
    """Independent bounded solver mirroring the shipping constraints.

    Returns up to two solutions plus (visited_nodes, backtracks, max_branching).
    The shipping Swift solver revalidates every emitted level in CI.
    """

    def region(row: int, column: int) -> int:
        return regions[row * size + column]

    placements = {row: column for row, column in clues}
    used_columns = {column for _, column in clues}
    used_regions = {region(row, column) for row, column in clues}

    if (
        len(placements) != len(clues)
        or len(used_columns) != len(clues)
        or len(used_regions) != len(clues)
    ):
        return [], (0, 0, 0)

    for index, (row, column) in enumerate(clues):
        for other_row, other_column in clues[:index]:
            if abs(other_row - row) <= 1 and abs(other_column - column) <= 1:
                return [], (0, 0, 0)

    solutions: list[tuple[int, ...]] = []
    visited_nodes = 0
    backtracks = 0
    max_branching = 0

    def candidates(row: int) -> list[int]:
        result: list[int] = []
        for column in range(size):
            if column in used_columns or region(row, column) in used_regions:
                continue
            if any(
                abs(existing_row - row) <= 1
                and abs(existing_column - column) <= 1
                for existing_row, existing_column in placements.items()
            ):
                continue
            result.append(column)
        return result

    def search() -> None:
        nonlocal visited_nodes, backtracks, max_branching
        if len(solutions) >= limit:
            return
        if len(placements) == size:
            solutions.append(tuple(placements[row] for row in range(size)))
            return

        choice: tuple[int, list[int]] | None = None
        for row in range(size):
            if row in placements:
                continue
            row_candidates = candidates(row)
            if not row_candidates:
                backtracks += 1
                return
            if (
                choice is None
                or len(row_candidates) < len(choice[1])
                or (len(row_candidates) == len(choice[1]) and row < choice[0])
            ):
                choice = (row, row_candidates)

        assert choice is not None
        row, row_candidates = choice
        max_branching = max(max_branching, len(row_candidates))

        for column in row_candidates:
            if len(solutions) >= limit:
                break
            visited_nodes += 1
            territory = region(row, column)
            placements[row] = column
            used_columns.add(column)
            used_regions.add(territory)

            has_dead_end = any(
                not candidates(unresolved_row)
                for unresolved_row in range(size)
                if unresolved_row not in placements
            )
            if has_dead_end:
                backtracks += 1
            else:
                search()

            del placements[row]
            used_columns.remove(column)
            used_regions.remove(territory)

    search()
    return solutions, (visited_nodes, backtracks, max_branching)


def accepted_candidate(
    size: int,
    seed: int,
    max_clues: int,
) -> tuple[tuple[int, ...], tuple[int, ...], tuple[tuple[int, int], ...], tuple[int, int, int], int] | None:
    regions = connected_partition(size, seed)
    solutions, metrics = solve(size, regions)
    if not solutions:
        return None

    target = solutions[0]
    if len(solutions) == 1:
        clues: tuple[tuple[int, int], ...] = ()
    else:
        found: tuple[tuple[int, int], ...] | None = None
        for clue_count in range(1, max_clues + 1):
            for rows in itertools.combinations(range(size), clue_count):
                attempt = tuple((row, target[row]) for row in rows)
                clue_solutions, clue_metrics = solve(size, regions, attempt)
                if len(clue_solutions) == 1 and clue_solutions[0] == target:
                    found = attempt
                    metrics = clue_metrics
                    break
            if found is not None:
                break
        if found is None:
            return None
        clues = found

    visited, backtracks, branching = metrics
    difficulty_score = (
        visited
        + 2 * backtracks
        + 8 * branching
        + 60 * (size - 6)
        - 25 * len(clues)
    )
    return regions, target, clues, metrics, difficulty_score


def build_pack() -> dict[str, object]:
    # First five are curated. The remaining portfolio deliberately spans 6×6 to 9×9.
    specs = ((6, 25, 0), (7, 25, 1), (8, 25, 2), (9, 20, 2))
    accepted: list[tuple[int, int, int, tuple[int, ...], tuple[int, ...], tuple[tuple[int, int], ...]]] = []
    seen: set[tuple[int, tuple[int, ...]]] = set()
    seed = BASE_SEED

    for size, required, max_clues in specs:
        count = 0
        while count < required:
            result = accepted_candidate(size, seed, max_clues)
            authoring_seed = seed
            seed += 1
            if result is None:
                continue
            regions, solution, clues, _metrics, score = result
            key = (size, regions)
            if key in seen:
                continue
            seen.add(key)
            accepted.append((size, score, authoring_seed, regions, solution, clues))
            count += 1

    # Difficulty is a progression signal, not just solver work: size and clue burden matter,
    # and within each size lower solver work appears earlier.
    accepted.sort(key=lambda item: (item[0], item[1], item[2]))
    levels = list(ONBOARDING)

    for order, item in enumerate(accepted, start=6):
        size, _score, authoring_seed, regions, solution, clues = item
        difficulty = min(5, 2 + ((order - 6) * 4 // 95))
        levels.append(
            {
                "id": f"v1-{order:03d}",
                "order": order,
                "kind": "standard",
                "size": size,
                "regionIDs": list(regions),
                "adjacencyRule": "noTouching",
                "initialMarkers": [
                    {"row": row, "column": column} for row, column in clues
                ],
                "solution": [
                    {"row": row, "column": solution[row]} for row in range(size)
                ],
                "difficulty": difficulty,
                "authoringSeed": authoring_seed,
            }
        )

    if len(levels) != TARGET_COUNT:
        raise RuntimeError(f"expected {TARGET_COUNT} levels, generated {len(levels)}")
    return {"schemaVersion": SCHEMA_VERSION, "levels": levels}


def encoded_pack() -> str:
    return json.dumps(build_pack(), indent=2, sort_keys=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", type=Path, metavar="PATH")
    group.add_argument("--check", type=Path, metavar="PATH")
    args = parser.parse_args()

    expected = encoded_pack()
    path: Path = args.write or args.check

    if args.write:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected, encoding="utf-8")
        print(f"wrote {TARGET_COUNT} deterministic levels to {path}")
        return 0

    actual = path.read_text(encoding="utf-8")
    if actual != expected:
        print(f"{path} is stale; run: python3 Tools/level_factory.py --write {path}")
        return 1
    print(f"{path} matches the deterministic {TARGET_COUNT}-level factory output")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
