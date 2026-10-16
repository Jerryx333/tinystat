#!/bin/bash
# Verify real chat grants, cancellation and long-conversation view/resource limits.
# Run: bash scripts/verify-conversation-ui.sh after scripts/build.sh
# Requires macOS AppKit; synthetic model, no remote calls or user writes.
set -euo pipefail
cd "$(dirname "$0")/.."
cat Sources/AssistantUI.swift tests/conversation-ui.swift > build/ConversationUIValidation.swift
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/Model.swift Sources/Diagnostics.swift Sources/Appearance.swift Sources/AssistantActions.swift Sources/AgentBackend.swift Sources/Conversation.swift Sources/Investigation.swift build/ConversationUIValidation.swift build/Telemetry.o build/AgentProcess.o -framework AppKit -framework IOKit -framework Security -o build/test-conversation-ui
build/test-conversation-ui
