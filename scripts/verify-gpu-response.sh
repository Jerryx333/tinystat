#!/bin/bash
# Probe GPU reader response using a four-second synthetic Metal workload.
# Run: bash scripts/verify-gpu-response.sh > report.json after scripts/build.sh.
# Requires macOS Apple Command Line Tools, Metal; briefly consumes GPU resources.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -parse-as-library -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h tests/gpu-response.swift build/Telemetry.o -framework Metal -framework IOKit -framework Foundation -o build/test-gpu-response
build/test-gpu-response
