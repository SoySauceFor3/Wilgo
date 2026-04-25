#!/usr/bin/env bash
set -euo pipefail

XCTEST_DIR="${HOME}/Library/Developer/XCTestDevices"
KEEP_HOURS="${KEEP_HOURS:-6}"

# Run the project test suite on the required simulator.
xcodebuild test \
  -project Wilgo.xcodeproj \
  -scheme Wilgo \
  -destination "platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588"

# Give test processes a moment to fully exit.
sleep 2

# Skip cleanup if a test process is still active.
if pgrep -f "xcodebuild|xctest" >/dev/null; then
  echo "Skip cleanup: test process is still running."
  exit 0
fi

# Remove only old XCTest clone directories.
if [[ -d "${XCTEST_DIR}" ]]; then
  /usr/bin/find "${XCTEST_DIR}" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -mmin "+$((KEEP_HOURS * 60))" \
    -print \
    -exec rm -rf {} +
fi
