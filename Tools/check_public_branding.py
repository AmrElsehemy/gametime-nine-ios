#!/usr/bin/env python3
"""Catch legacy branding in app literals; identifiers are explicitly reviewed.

This source check complements the bundled display-name test and visual QA.
It cannot inspect rendered images or text assembled dynamically at runtime.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LEGACY = re.compile(r"\bnine\b", re.IGNORECASE)
LITERAL = re.compile(r'"(?:\\.|[^"\\])*"')
# Exact technical literals only. Never add player-facing copy here.
INTERNAL = {
    '--nine-capture',
    'Nine capture requires at least one validated bundled level',
    'Nine requires at least one validated bundled level',
    r'nine-replay-\(replay.replayID.uuidString).json',
    'nine.preferences.soundEnabled',
    'nine.preferences.hapticsEnabled',
    'nine.analytics.firstOpenSent',
    'ai.knowlly.nine.daily.time',
    'ai.knowlly.nine.achievement.first-solve',
    'ai.knowlly.nine.achievement.tutorial-complete',
    'ai.knowlly.nine.achievement.first-daily',
    'ai.knowlly.nine.achievement.streak-7',
    'nine.onboarding.completed.v1',
    r'Invalid bundled Nine level pack: \(error)',
    'nine.progress.save.v2',
    r'nine-daily-v1|\(NineUTCDate.dayKey(for: date))',
}


def violations(source):
    return [m.group()[1:-1] for m in LITERAL.finditer(source)
            if LEGACY.search(m.group()) and m.group()[1:-1] not in INTERNAL]


def main():
    errors = []
    for path in sorted((ROOT / 'Nine').rglob('*')):
        if path.suffix in {'.swift', '.strings', '.xcstrings'}:
            errors.extend(f'{path.relative_to(ROOT)}: {s}'
                          for s in violations(path.read_text()))
    project = (ROOT / 'Nine.xcodeproj/project.pbxproj').read_text()
    names = re.findall(r'INFOPLIST_KEY_CFBundleDisplayName\s*=\s*([^;]+);', project)
    if names != ['"Exactly One"', '"Exactly One"']:
        errors.append(f'Debug/Release display names are incorrect: {names}')
    compositor = (ROOT / 'Tools/compose_app_store_screenshots.py').read_text()
    if 'brand = "EXACTLY ONE   ·   KNOWLLY GAMES"' not in compositor:
        errors.append('Screenshot brand line differs from the approved identity')
    if errors:
        raise SystemExit('\n'.join(errors))
    print('Public branding source checks passed')


if __name__ == '__main__':
    main()
