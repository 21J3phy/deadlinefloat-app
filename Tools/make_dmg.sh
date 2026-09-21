#!/usr/bin/env bash
#
# Packs a built DeadlineFloat.app into a disk image with a laid-out Finder
# window: the app on the left, Applications on the right, and an arrow between
# them on the backdrop Tools/make_dmg_background.swift draws.
#
#   Tools/make_dmg.sh build/Release/DeadlineFloat.app build/DeadlineFloat-1.0.dmg
#
# Tools/build_release.sh calls this; it is separate so the packaging can be
# re-run without rebuilding, which is most of what you want while adjusting how
# the window looks.
#
set -euo pipefail

APP="${1:?usage: make_dmg.sh <app> <output.dmg>}"
DMG="${2:?usage: make_dmg.sh <app> <output.dmg>}"
VOLUME_NAME="${DMG_VOLUME_NAME:-DeadlineFloat}"

cd "$(dirname "$0")/.."
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
DMG_DIR="$(cd "$(dirname "$DMG")" && pwd)"
DMG="$DMG_DIR/$(basename "$DMG")"

[[ -d "$APP" ]] || { echo "✗ no app bundle at $APP" >&2; exit 1; }

# These numbers are also in Tools/make_dmg_background.swift, which draws the
# wells and the arrow to match. Change them together.
WINDOW_WIDTH=660
WINDOW_HEIGHT=420
ICON_BASELINE=200
APP_CENTRE_X=175
APPLICATIONS_CENTRE_X=485

STAGING="$(mktemp -d)"
SCRATCH="$(mktemp -d)"
MOUNTPOINT=""
cleanup() {
  [[ -n "$MOUNTPOINT" && -d "$MOUNTPOINT" ]] && hdiutil detach "$MOUNTPOINT" -force >/dev/null 2>&1 || true
  rm -rf "$STAGING" "$SCRATCH"
}
trap cleanup EXIT

echo "▸ Staging…"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$STAGING/.background"
swift Tools/make_dmg_background.swift "$SCRATCH/background" >/dev/null
# One TIFF holding both representations: the Finder picks the right one per
# display, which a lone PNG cannot express.
tiffutil -cathidpicheck \
  "$SCRATCH/background/background.png" \
  "$SCRATCH/background/background@2x.png" \
  -out "$STAGING/.background/background.tiff" >/dev/null

# The mounted volume carries the app's own icon rather than the generic disk.
if [[ -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  cp "$APP/Contents/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
fi

echo "▸ Creating a writable image…"
# Room for the app plus the Finder's own bookkeeping, which needs slack to
# write .DS_Store into.
SIZE_KB=$(( $(du -sk "$STAGING" | cut -f1) + 20000 ))
hdiutil create -srcfolder "$STAGING" -volname "$VOLUME_NAME" \
  -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW \
  -size "${SIZE_KB}k" -ov "$SCRATCH/rw.dmg" >/dev/null

MOUNTPOINT="/Volumes/$VOLUME_NAME"
hdiutil attach "$SCRATCH/rw.dmg" -readwrite -noverify -noautoopen -mountpoint "$MOUNTPOINT" >/dev/null
# hdiutil returns before the volume is settled often enough to matter.
for _ in $(seq 1 20); do [[ -d "$MOUNTPOINT" ]] && break; sleep 0.5; done

SetFile -a V "$MOUNTPOINT/.background" 2>/dev/null || true
if [[ -f "$MOUNTPOINT/.VolumeIcon.icns" ]]; then
  SetFile -a CV "$MOUNTPOINT/.VolumeIcon.icns" 2>/dev/null || true
  SetFile -a C "$MOUNTPOINT" 2>/dev/null || true
else
  echo "  ⚠ no .VolumeIcon.icns on the volume — it will mount with the generic disk icon"
fi

echo "▸ Laying out the window…"
# The Finder writes the window's geometry into .DS_Store lazily. Everything is
# set on one open window, flushed with `update`, and only then closed; opening
# and closing repeatedly loses the bounds, which is how you end up with a
# clipped window and a scrollbar over the backdrop.
osascript <<APPLESCRIPT >/dev/null || echo "  ⚠ the Finder refused to lay the window out; the image is still valid"
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    delay 1
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set the bounds of theWindow to {200, 150, $((200 + WINDOW_WIDTH)), $((150 + WINDOW_HEIGHT))}
    set theViewOptions to the icon view options of theWindow
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set text size of theViewOptions to 12
    set label position of theViewOptions to bottom
    set shows item info of theViewOptions to false
    set shows icon preview of theViewOptions to true
    set background picture of theViewOptions to file ".background:background.tiff"
    set position of item "DeadlineFloat.app" of theWindow to {$APP_CENTRE_X, $ICON_BASELINE}
    set position of item "Applications" of theWindow to {$APPLICATIONS_CENTRE_X, $ICON_BASELINE}
    delay 1
    update without registering applications
    delay 3
    close
  end tell
end tell
APPLESCRIPT

# Nothing above guarantees .DS_Store has reached the disk; detaching too early
# throws the whole layout away.
for _ in $(seq 1 10); do [[ -s "$MOUNTPOINT/.DS_Store" ]] && break; sleep 0.5; done

# Spotlight's journal is recreated for as long as the volume is mounted
# read-write, so it can only be swept up at the very end — otherwise it is
# baked into the finished image, where it shows up for anyone browsing with
# hidden files turned on.
rm -rf "$MOUNTPOINT/.fseventsd" "$MOUNTPOINT/.Trashes" "$MOUNTPOINT/.TemporaryItems" 2>/dev/null || true
sync
sleep 1
hdiutil detach "$MOUNTPOINT" -force >/dev/null
MOUNTPOINT=""

echo "▸ Compressing…"
rm -f "$DMG"
# ULFO (LZFSE) is smaller and faster to open than UDZO, and is read by every
# macOS this app supports.
hdiutil convert "$SCRATCH/rw.dmg" -format ULFO -o "$DMG" >/dev/null
hdiutil internet-enable -no "$DMG" >/dev/null 2>&1 || true

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
