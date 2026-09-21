#!/usr/bin/env bash
#
# Builds, signs, notarises and packages DeadlineFloat for distribution outside
# the App Store — the whole path from source to something another person can
# download and open without macOS stopping them.
#
#   Tools/build_release.sh                  # build, sign, notarise, staple, package
#   Tools/build_release.sh --no-notarize    # skip the round trip to Apple
#   Tools/build_release.sh --no-dmg         # zip only
#
# What it needs, once, on this Mac:
#
#   • A "Developer ID Application" certificate in the login keychain. Apple only
#     issues these to the Account Holder, from
#     developer.apple.com/account/resources/certificates — pick the G2 Sub-CA.
#   • A notarytool keychain profile. See Secrets/SIGNING.md; the short version is
#       xcrun notarytool store-credentials deadlinefloat \
#         --key <AuthKey_XXXX.p8> --key-id XXXX --issuer <issuer-uuid>
#   • Secrets/GoogleOAuth.plist, the OAuth client. Git-ignored, embedded here.
#
# Overrides:
#   DEADLINEFLOAT_TEAM            team id                 (default GK2Z5G7FG9)
#   DEADLINEFLOAT_IDENTITY        signing identity        (default: the Developer ID in the keychain)
#   DEADLINEFLOAT_NOTARY_PROFILE  notarytool profile name (default deadlinefloat)
#
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARIZE=1
MAKE_DMG=1
for arg in "$@"; do
  case "$arg" in
    --no-notarize) NOTARIZE=0 ;;
    --no-dmg) MAKE_DMG=0 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

DERIVED=".build/ReleaseBuild"
OUTPUT="build"
TEAM="${DEADLINEFLOAT_TEAM:-GK2Z5G7FG9}"
NOTARY_PROFILE="${DEADLINEFLOAT_NOTARY_PROFILE:-deadlinefloat}"

# ── The signing identity ──────────────────────────────────────────────────────
# Developer ID is the only kind of signature Gatekeeper accepts for an app that
# arrives by download. An Apple Development certificate builds and runs fine on
# this Mac and fails on every other one, so say so rather than shipping it.
IDENTITY="${DEADLINEFLOAT_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
fi
if [[ -z "$IDENTITY" ]]; then
  cat >&2 <<'EOF'
✗ No "Developer ID Application" certificate in the keychain.

  Without one the build can only be signed for this Mac. Create one at
  https://developer.apple.com/account/resources/certificates/add (Software →
  Developer ID Application → G2 Sub-CA), signed in as the Account Holder, then
  re-run. Set DEADLINEFLOAT_IDENTITY to override the choice.
EOF
  exit 1
fi
echo "▸ Signing as: $IDENTITY"

# ── Build ─────────────────────────────────────────────────────────────────────
echo "▸ Building Release…"
xcodebuild \
  -project DeadlineFloat.xcodeproj \
  -scheme DeadlineFloat \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS,arch=$(uname -m)" \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build | grep -E "^(\*\*|error:|warning: .*deprecat)" || true

BUILT="$DERIVED/Build/Products/Release/DeadlineFloat.app"
[[ -d "$BUILT" ]] || { echo "✗ the build produced no app bundle" >&2; exit 1; }

rm -rf "$OUTPUT/Release"
mkdir -p "$OUTPUT/Release"
cp -R "$BUILT" "$OUTPUT/Release/"
APP="$OUTPUT/Release/DeadlineFloat.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "▸ DeadlineFloat $VERSION ($BUILD_NUMBER)"

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
else
  echo "⚠ $SECRETS not found — this build will have no OAuth client and cannot sign in."
  echo "  Copy Secrets/GoogleOAuth.plist.example and fill it in, or use"
  echo "  Settings → Account → Advanced in the running app."
fi

# ── Sign ──────────────────────────────────────────────────────────────────────
# Re-sign after adding the plist, from the entitlements file in the repository
# rather than the .xcent the build left behind: an ordinary (non-archive) Release
# build injects com.apple.security.get-task-allow, and re-signing with that would
# ship a debuggable app. The four keys in the file are the same ones the build
# used otherwise, so the Keychain access group is unchanged and tokens survive.
# --timestamp and -o runtime are not optional: notarisation rejects a bundle
# without a secure timestamp or the hardened runtime.
ENTITLEMENTS="DeadlineFloat/DeadlineFloat.entitlements"
echo "▸ Signing with $(basename "$ENTITLEMENTS")…"
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" --generate-entitlement-der "$APP"

echo "▸ Verifying…"
codesign --verify --deep --strict --verbose=2 "$APP"

# Three things that are each silently wrong rather than loudly wrong, and each
# of which would only show up on somebody else's Mac.
SIGNATURE="$(codesign --display --verbose=4 "$APP" 2>&1)"
ENTITLED="$(codesign --display --entitlements - --xml "$APP" 2>/dev/null | plutil -convert xml1 -o - -)"

# A signature carrying no secure timestamp notarises and then stops launching
# the day the certificate expires; catch that here rather than in five years.
grep -q "^Timestamp=" <<<"$SIGNATURE" \
  || { echo "✗ the signature has no secure timestamp" >&2; exit 1; }
# Without the hardened runtime, notarisation refuses the bundle outright.
grep -q "flags=.*runtime" <<<"$SIGNATURE" \
  || { echo "✗ the signature does not enable the hardened runtime" >&2; exit 1; }
# get-task-allow lets any process attach a debugger to the app and read the
# OAuth tokens straight out of its memory. Xcode injects it into ordinary
# (non-archive) builds, so a release has to be checked, not assumed.
if grep -q "get-task-allow" <<<"$ENTITLED"; then
  echo "✗ the app is signed with get-task-allow — that must never ship" >&2
  exit 1
fi
grep -E "Authority|TeamIdentifier|Timestamp|flags|Identifier" <<<"$SIGNATURE" | sed 's/^/    /'
grep -E "key>|true|false" <<<"$ENTITLED" | sed 's/^/    /'

# ── Package ───────────────────────────────────────────────────────────────────
ZIP="$OUTPUT/DeadlineFloat-$VERSION.zip"
echo "▸ Zipping…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# ── Notarise ──────────────────────────────────────────────────────────────────
notarise() {
  local what="$1"
  echo "▸ Notarising $(basename "$what")… (Apple usually answers within a few minutes)"
  xcrun notarytool submit "$what" --keychain-profile "$NOTARY_PROFILE" --wait \
    | sed 's/^/    /' | tee /tmp/deadlinefloat-notary.log
  grep -q "status: Accepted" /tmp/deadlinefloat-notary.log || {
    local id
    id="$(sed -n 's/.*id: \([0-9a-f-]\{36\}\).*/\1/p' /tmp/deadlinefloat-notary.log | head -1)"
    echo "✗ notarisation did not come back Accepted." >&2
    [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    exit 1
  }
}

if [[ "$NOTARIZE" == 1 ]]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "✗ no notarytool keychain profile called \"$NOTARY_PROFILE\" — see Secrets/SIGNING.md" >&2
    exit 1
  fi
  notarise "$ZIP"
  # The ticket is stapled to the app, not to the zip, so the zip is rebuilt from
  # the stapled bundle. That is what lets the app open on a Mac that is offline.
  echo "▸ Stapling the app…"
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
else
  echo "⚠ Skipping notarisation — this build will be stopped by Gatekeeper on any other Mac."
fi

DMG=""
if [[ "$MAKE_DMG" == 1 ]]; then
  DMG="$OUTPUT/DeadlineFloat-$VERSION.dmg"
  Tools/make_dmg.sh "$APP" "$DMG"
  if [[ "$NOTARIZE" == 1 ]]; then
    # The disk image is notarised in its own right: it is the file people
    # download, and Gatekeeper checks it before anything inside it.
    notarise "$DMG"
    echo "▸ Stapling the disk image…"
    xcrun stapler staple "$DMG"
  fi
fi

# ── Prove it ──────────────────────────────────────────────────────────────────
echo "▸ Gatekeeper:"
spctl --assess --type execute --verbose=4 "$APP" 2>&1 | sed 's/^/    /' || true
xcrun stapler validate "$APP" 2>&1 | sed 's/^/    /' || true
if [[ -n "$DMG" && "$NOTARIZE" == 1 ]]; then
  xcrun stapler validate "$DMG" 2>&1 | sed 's/^/    /' || true
fi

echo "▸ Checksums:"
( cd "$OUTPUT" && shasum -a 256 "$(basename "$ZIP")" ${DMG:+"$(basename "$DMG")"} \
  | tee "SHA256SUMS.txt" | sed 's/^/    /' )

echo
echo "DeadlineFloat $VERSION ($BUILD_NUMBER)"
echo "  app  $APP"
echo "  zip  $ZIP"
[[ -n "$DMG" ]] && echo "  dmg  $DMG"
echo
if [[ "$NOTARIZE" == 1 ]]; then
  echo "Notarised and stapled. Opens on any Mac running macOS 14 or later."
else
  echo "Not notarised — fine on this Mac, blocked on every other one."
fi
