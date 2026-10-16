#!/bin/bash
# Show a synthetic native chat for visual verification without sending any data.
# Run: bash scripts/preview-chat.sh after scripts/build.sh; quit the preview app with Cmd+Q.
# Requires macOS Apple Command Line Tools and an interactive login session.
set -euo pipefail
cd "$(dirname "$0")/.."
cat Sources/AssistantUI.swift tests/chat-preview.swift > build/AssistantUIPreview.swift
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/Model.swift Sources/Diagnostics.swift Sources/Appearance.swift Sources/AssistantActions.swift Sources/AgentBackend.swift build/AssistantUIPreview.swift build/Telemetry.o build/AgentProcess.o -framework AppKit -framework IOKit -framework Security -o build/chat-preview
mkdir -p build/ChatPreview.app/Contents/MacOS
cp build/chat-preview build/ChatPreview.app/Contents/MacOS/ChatPreview
cat > build/ChatPreview.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>ChatPreview</string><key>CFBundleIdentifier</key><string>local.tinystat.chatpreview</string><key>CFBundleName</key><string>ChatPreview</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
codesign --force --sign - build/ChatPreview.app
open build/ChatPreview.app
