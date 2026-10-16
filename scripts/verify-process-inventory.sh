#!/bin/bash
# Verify and measure local process inventory with no model calls or process-name output.
# Run: bash scripts/verify-process-inventory.sh after scripts/build.sh
# Requires macOS Apple Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/Model.swift Sources/Diagnostics.swift tests/process-inventory.swift build/Telemetry.o -framework AppKit -framework IOKit -o build/test-process-inventory
build/test-process-inventory
