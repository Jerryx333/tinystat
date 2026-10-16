#!/bin/bash
# Verify native composer geometry and keyboard handling without sending a request.
# Run: bash scripts/verify-ui.sh
# Requires macOS Apple Command Line Tools and an interactive login session.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 Sources/Appearance.swift tests/composer.swift -framework AppKit -o build/test-composer
build/test-composer
