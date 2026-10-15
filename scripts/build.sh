#!/bin/bash
# Build TinyStat.app locally; run: bash scripts/build.sh
# Requires macOS Apple Command Line Tools; no downloaded dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/TinyStat.app/Contents/MacOS
xcrun clang -arch arm64 -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 -c Sources/Telemetry.c -o build/Telemetry.o
xcrun swiftc -Osize -whole-module-optimization -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/*.swift build/Telemetry.o -framework AppKit -framework IOKit -framework ServiceManagement -o build/TinyStat.app/Contents/MacOS/TinyStat
cp Info.plist build/TinyStat.app/Contents/Info.plist
codesign --force --sign - build/TinyStat.app
printf 'Built: %s/build/TinyStat.app\n' "$PWD"
du -sh build/TinyStat.app
