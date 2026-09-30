#!/usr/bin/env python3
"""Catch the retired codename "Nine" in app sources, file names and literals.

The codename was replaced by Exactly One / ExactlyOne before the first
release. This source check complements the bundled display-name test and
visual QA. It cannot inspect rendered images or text assembled at runtime.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LEGACY = re.compile(r"\bnine\b", re.IGNORECASE)
# Identifiers such as NineBoardState. "NineByNine" (a 9×9 board) has no word
# boundary before "Nine", so it is not flagged.
LEGACY_IDENTIFIER = re.compile(r"\bNine(?=[A-Z_])")
LITERAL = re.compile(r'"(?:\\.|[^"\\])*"')
SOURCES = ('ExactlyOne', 'ExactlyOneTests')


def violations(source):
    found = [m.group()[1:-1] for m in LITERAL.finditer(source) if LEGACY.search(m.group())]
    found += [m.group() for m in LEGACY_IDENTIFIER.finditer(source)]
    return found


def main():
    errors = []
    for folder in SOURCES:
        for path in sorted((ROOT / folder).rglob('*')):
            if 'nine' in path.name.lower():
                errors.append(f'{path.relative_to(ROOT)}: file name uses the retired codename')
            if path.suffix in {'.swift', '.strings', '.xcstrings'}:
                errors.extend(f'{path.relative_to(ROOT)}: {s}'
                              for s in violations(path.read_text()))
    project = (ROOT / 'ExactlyOne.xcodeproj/project.pbxproj').read_text()
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
