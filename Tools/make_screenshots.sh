#!/usr/bin/env bash
#
# Regenerates the previews in Docs/screenshots.
#
# DeadlineFloat ships sandboxed, and since macOS 14 one process cannot read
# another app's container, so a sandboxed build has nowhere to write that this
# script could read back. The previews are therefore produced by an unsandboxed
# copy of the same build, writing to a temporary directory that is then copied
# into the repository.
#
# The app renders its real views over a synthetic desktop and exits; it never
# opens a window, touches the Keychain or contacts Google.
#
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED=".build/PreviewBuild"
STAGING="$(mktemp -d /tmp/deadlinefloat-shots.XXXXXX)"
OUTPUT="docs/screenshots"

echo "▸ Building an unsandboxed preview copy…"
xcodebuild \
  -project DeadlineFloat.xcodeproj \
  -scheme DeadlineFloat \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS,arch=$(uname -m)" \
  CODE_SIGN_ENTITLEMENTS="" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=NO \
  build >/dev/null

echo "▸ Rendering…"
"$DERIVED/Build/Products/Debug/DeadlineFloat.app/Contents/MacOS/DeadlineFloat" \
  --render-screenshots "$STAGING"

mkdir -p "$OUTPUT"
cp "$STAGING"/*.png "$OUTPUT"/
rm -rf "$STAGING"

echo "▸ Wrote:"
ls -1 "$OUTPUT"
