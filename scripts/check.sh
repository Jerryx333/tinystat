#!/bin/bash
# Build and validate public documentation; run: bash scripts/check.sh
# Requires macOS Apple Command Line Tools and Python 3; no hardware sensor assumptions.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
codesign --verify --strict build/TinyStat.app
bash -n scripts/*.sh
python3 scripts/check_docs.py
