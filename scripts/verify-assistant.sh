#!/bin/bash
# Verify assistant contracts and owned subprocess cleanup without model calls.
# Run: bash scripts/verify-assistant.sh
# Requires macOS Apple Command Line Tools; build first with scripts/build.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/Model.swift Sources/Diagnostics.swift Sources/AssistantActions.swift Sources/AgentBackend.swift tests/assistant.swift build/Telemetry.o build/AgentProcess.o -framework AppKit -framework IOKit -framework Security -o build/test-assistant
build/test-assistant
