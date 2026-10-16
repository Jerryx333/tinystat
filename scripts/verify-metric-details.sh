#!/bin/bash
# Validate and render synthetic metric inspectors without model calls.
# Run: bash scripts/verify-metric-details.sh after scripts/build.sh.
# Requires macOS Apple Command Line Tools and AppKit.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/Model.swift Sources/Diagnostics.swift Sources/AssistantActions.swift Sources/AgentBackend.swift Sources/Appearance.swift Sources/Interface.swift Sources/MetricDetails.swift tests/metric-details.swift build/Telemetry.o build/AgentProcess.o -framework AppKit -framework IOKit -framework Security -o build/test-metric-details
build/test-metric-details
