#!/usr/bin/env bash
#
# Builds a signed release copy of DeadlineFloat.app into build/Release and zips
# it for distribution.
#
#   Tools/build_release.sh                 # sign with the project's team
#   DEADLINEFLOAT_TEAM=ABCDE12345 Tools/build_release.sh
#   DEADLINEFLOAT_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" \
#     Tools/build_release.sh               # for distribution outside the App Store
#
# Notarising (needed before anyone else can open the app without a warning):
#
#   xcrun notarytool submit build/DeadlineFloat.zip \
#     --apple-id you@example.com --team-id ABCDE12345 --password <app-specific-password> --wait
#   xcrun stapler staple build/Release/DeadlineFloat.app
#
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED=".build/ReleaseBuild"
OUTPUT="build"
TEAM="${DEADLINEFLOAT_TEAM:-}"
IDENTITY="${DEADLINEFLOAT_IDENTITY:-}"

ARGS=(
  -project DeadlineFloat.xcodeproj
  -scheme DeadlineFloat
  -configuration Release
  -derivedDataPath "$DERIVED"
  -destination "platform=macOS,arch=$(uname -m)"
)
[[ -n "$TEAM" ]] && ARGS+=(DEVELOPMENT_TEAM="$TEAM")
if [[ -n "$IDENTITY" ]]; then
  ARGS+=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual)
fi

echo "▸ Building Release…"
xcodebuild "${ARGS[@]}" build

APP="$DERIVED/Build/Products/Release/DeadlineFloat.app"
rm -rf "$OUTPUT/Release"
mkdir -p "$OUTPUT/Release"
cp -R "$APP" "$OUTPUT/Release/"
APP="$OUTPUT/Release/DeadlineFloat.app"

# ── Credentials ───────────────────────────────────────────────────────────────
# The OAuth client lives in Secrets/GoogleOAuth.plist, which is git-ignored, so
# the client secret never appears in public source where GitHub's scanning would
# report it to Google. It is copied into the bundle here and the app re-signed,
# which is what makes a released build sign in with one button.
SECRETS="Secrets/GoogleOAuth.plist"
if [[ -f "$SECRETS" ]]; then
  CLIENT_ID="$(/usr/libexec/PlistBuddy -c 'Print :ClientID' "$SECRETS" 2>/dev/null || true)"
  CLIENT_SECRET="$(/usr/libexec/PlistBuddy -c 'Print :ClientSecret' "$SECRETS" 2>/dev/null || true)"

  if [[ -z "$CLIENT_ID" || "$CLIENT_ID" != *".apps.googleusercontent.com" ]]; then
    echo "✗ $SECRETS has no usable ClientID (must end in .apps.googleusercontent.com)" >&2
    exit 1
  fi
  if [[ -z "$CLIENT_SECRET" ]]; then
    # This client's token endpoint answers "client_secret is missing" without it,
    # so a build lacking it would fail for every user who has no local override.
    echo "✗ $SECRETS has no ClientSecret — this OAuth client requires one" >&2
    exit 1
  fi

  echo "▸ Embedding OAuth client ${CLIENT_ID%%-*}…"
  cp "$SECRETS" "$APP/Contents/Resources/GoogleOAuth.plist"

  # Re-sign, reusing exactly the entitlements and identity the build used, so the
  # app keeps the same Keychain access and existing tokens stay valid.
  XCENT="$(/usr/bin/find "$DERIVED" -name 'DeadlineFloat.app.xcent' -print -quit)"
  SIGN_ID="${IDENTITY:-$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/ && !seen { print $2; seen = 1 }')}"
  if [[ -z "$SIGN_ID" || -z "$XCENT" ]]; then
    echo "✗ could not determine the signing identity or entitlements to re-sign with" >&2
    exit 1
  fi
  if [[ "$SIGN_ID" == *"Developer ID"* ]]; then TS=(--timestamp); else TS=(--timestamp=none); fi

  codesign --force --sign "$SIGN_ID" -o runtime \
    --entitlements "$XCENT" --generate-entitlement-der "${TS[@]}" "$APP"
else
  echo "⚠ $SECRETS not found — this build will have no OAuth client and cannot sign in."
  echo "  Copy Secrets/GoogleOAuth.plist.example and fill it in, or use"
  echo "  Settings → Account → Advanced in the running app."
fi

echo "▸ Signature:"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | sed 's/^/    /'

echo "▸ Zipping…"
rm -f "$OUTPUT/DeadlineFloat.zip"
ditto -c -k --keepParent "$APP" "$OUTPUT/DeadlineFloat.zip"

echo
echo "Built  $OUTPUT/Release/DeadlineFloat.app"
echo "Zipped $OUTPUT/DeadlineFloat.zip"
echo
echo "Drag DeadlineFloat.app to /Applications — Launch at Login needs it there."
