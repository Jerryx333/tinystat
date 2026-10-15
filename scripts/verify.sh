#!/bin/bash
# Verify real M1 telemetry and CPU time units; run: bash scripts/verify.sh
# Requires Apple Command Line Tools; no downloaded dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
mkdir -p build
for test in probe cpu-time; do
  xcrun clang -arch arm64 -O2 -Wall -Wextra -Werror Sources/Telemetry.c "tests/$test.c" -framework IOKit -framework CoreFoundation -o "build/test-$test"
  "build/test-$test"
done
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Telemetry.h Sources/Model.swift tests/sampling.swift build/Telemetry.o -framework AppKit -framework IOKit -o build/test-sampling
build/test-sampling
codesign --verify --strict build/TinyStat.app
