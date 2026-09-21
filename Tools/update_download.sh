#!/usr/bin/env bash
#
# Rewrites the download block on the website from what is actually in build/, so
# the version, the size and the checksums on the page are the ones in the file
# people are downloading rather than whatever was true last time.
#
#   Tools/build_release.sh && Tools/update_download.sh
#
# The block is delimited by <!-- download:start --> / <!-- download:end --> in
# docs/index.html; everything between them is regenerated.
#
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${DEADLINEFLOAT_SITE_REPO:-21J3phy/deadlinefloat}"
PAGE="docs/index.html"

APP="build/Release/DeadlineFloat.app"
[[ -d "$APP" ]] || { echo "✗ no build/Release/DeadlineFloat.app — run Tools/build_release.sh first" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

DMG="build/DeadlineFloat-$VERSION.dmg"
ZIP="build/DeadlineFloat-$VERSION.zip"
for f in "$DMG" "$ZIP"; do
  [[ -f "$f" ]] || { echo "✗ missing $f" >&2; exit 1; }
done

# A download the user cannot open is worse than no download, so refuse to
# advertise an artefact Apple has not stapled.
xcrun stapler validate "$DMG" >/dev/null 2>&1 \
  || { echo "✗ $DMG carries no notarisation ticket — do not publish it" >&2; exit 1; }

DMG_SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
ZIP_SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')B"
BASE="https://github.com/$REPO/releases/download/v$VERSION"

BLOCK="$(cat <<HTML
    <div class="download">
      <a class="get" href="$BASE/DeadlineFloat-$VERSION.dmg">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1"
             stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M12 3v12"></path><path d="M7 12l5 5 5-5"></path><path d="M4 21h16"></path>
        </svg>
        Download for Mac
      </a>
      <p class="meta">
        Version $VERSION · $SIZE · macOS 14 or later · Apple silicon and Intel<br>
        Signed and notarised by Apple. <a href="$BASE/DeadlineFloat-$VERSION.zip">Zip instead</a>
      </p>
      <details class="sums">
        <summary>Verify the download</summary>
<pre>shasum -a 256 DeadlineFloat-$VERSION.dmg
$DMG_SHA  DeadlineFloat-$VERSION.dmg
$ZIP_SHA  DeadlineFloat-$VERSION.zip</pre>
      </details>
    </div>
HTML
)"

BLOCK="$BLOCK" VERSION="$VERSION" python3 - "$PAGE" <<'PY'
import os, re, sys
page = sys.argv[1]
html = open(page).read()
start, end = "<!-- download:start", "<!-- download:end -->"
i, j = html.index(start), html.index(end)
i = html.index("\n", i) + 1
html = html[:i] + os.environ["BLOCK"] + "\n    " + html[j:]
open(page, "w").write(html)
print(f"Wrote the {os.environ['VERSION']} download block into {page}")
PY
