#!/bin/bash
# Exercise three live Claude diagnostic decisions with synthetic data only.
# Run: bash scripts/verify-assistant-quality-live.sh after scripts/build.sh
# Requires authenticated native Claude; uses model quota, no machine telemetry sent.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/Model.swift Sources/Diagnostics.swift Sources/AgentBackend.swift tests/assistant-quality-live.swift build/Telemetry.o build/AgentProcess.o -framework AppKit -framework IOKit -framework Security -o build/test-assistant-quality-live
build/test-assistant-quality-live "$@"
