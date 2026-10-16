#!/bin/bash
# Validate investigation and bounded local archive contracts with synthetic data.
# Run: bash scripts/verify-assistant-v2.sh after scripts/build.sh
# Requires macOS Apple SDK; no external model calls or user-process actions.
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/Model.swift Sources/Diagnostics.swift Sources/AssistantActions.swift Sources/Conversation.swift Sources/Investigation.swift tests/assistant-v2.swift build/Telemetry.o build/AgentProcess.o -framework AppKit -framework IOKit -framework Security -o build/test-assistant-v2
build/test-assistant-v2
xcrun clang -O2 -Wall -Wextra -Werror tests/stop-target.c -o build/test-stop-target
codesign --force --sign - build/test-stop-target
build/test-stop-target &
fixture_pid=$!
# This shell owns the unreaped fixture PID; never signal a discovered user process.
trap 'kill -TERM "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true' EXIT
build/test-assistant-v2 --stop-fixture "$fixture_pid"
wait "$fixture_pid" || fixture_status=$?
[[ "${fixture_status:-0}" == 143 ]]
trap - EXIT
