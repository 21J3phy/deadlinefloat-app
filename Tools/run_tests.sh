#!/usr/bin/env bash
# Builds and runs the whole test suite.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild \
  -project DeadlineFloat.xcodeproj \
  -scheme DeadlineFloat \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  -destination "platform=macOS,arch=$(uname -m)" \
  test
