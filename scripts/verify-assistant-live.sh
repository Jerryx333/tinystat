#!/bin/bash
# Optional real model check; sends a synthetic greeting only, never telemetry.
# Run: bash scripts/verify-assistant-live.sh claude
# Requires Apple SDK and an installed, authenticated CLI; may consume model quota.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/Model.swift Sources/Diagnostics.swift Sources/AgentBackend.swift tests/assistant-live.swift build/Telemetry.o build/AgentProcess.o -framework AppKit -framework IOKit -framework Security -o build/test-assistant-live
build/test-assistant-live "${1:-claude}"
