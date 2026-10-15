#!/usr/bin/env python3
# Validate public Markdown links and license consistency.
# Run: python3 scripts/check_docs.py; requires Python 3 standard library.
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
readmes = [root / 'README.md', root / 'README.en.md']
license_text = (root / 'LICENSE').read_text()
license_name = 'Apache-2.0' if 'Apache License' in license_text else 'MIT' if 'MIT License' in license_text else None
assert license_name, 'Missing or unsupported license'
counts = []
for path in readmes:
    text = path.read_text()
    assert '[中文](README.md) | [English](README.en.md)' in '\n'.join(text.splitlines()[:6]), path
    assert license_name in text, f'{path}: license mismatch'
    counts.append(len(re.findall(r'^## ', text, re.M)))
assert len(set(counts)) == 1, 'README section counts differ'
files = list(root.glob('*.md')) + list((root / 'docs').glob('*.md'))
for path in files:
    text = path.read_text()
    assert '/Users/' not in text, f'{path}: private absolute path'
    for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', text):
        if re.match(r'^[a-z]+://', target) or target.startswith('#'):
            continue
        relative = target.split('#', 1)[0]
        assert (path.parent / relative).exists(), f'{path}: missing {target}'
print(f'Documentation OK: {len(files)} Markdown files, {license_name}')
