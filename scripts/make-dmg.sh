#!/bin/bash
# Builds the installer disk image: Pendant.app, a shortcut to /Applications and a night-sky background (scripts/dmg/background.swift).
# The window layout is set through Finder (AppleScript); if that is not allowed the image is still made, just without the layout.
# Usage: scripts/make-dmg.sh <Pendant.app> <output.dmg>
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:?usage: scripts/make-dmg.sh <Pendant.app> <output.dmg>}"
output="${2:?usage: scripts/make-dmg.sh <Pendant.app> <output.dmg>}"
volume="Pendant"
work=$(mktemp -d "${TMPDIR:-/tmp}/pendant-dmg.XXXXXX")
trap 'hdiutil detach "/Volumes/$volume" -force >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

# A leftover mount with the same name would make Finder address the wrong disk.
hdiutil detach "/Volumes/$volume" -force >/dev/null 2>&1 || true

mkdir -p "$work/stage/.background"
ditto "$app" "$work/stage/Pendant.app"
ln -s /Applications "$work/stage/Applications"
swift scripts/dmg/background.swift "$work/art" >/dev/null
tiffutil -cathidpicheck "$work/art/background.png" "$work/art/background@2x.png" -out "$work/stage/.background/background.tiff" >/dev/null 2>&1

rm -f "$work/rw.dmg"
hdiutil create -srcfolder "$work/stage" -volname "$volume" -fs HFS+ -format UDRW -ov "$work/rw.dmg" >/dev/null
hdiutil attach "$work/rw.dmg" -readwrite -noverify -noautoopen -mountpoint "/Volumes/$volume" >/dev/null

if ! osascript >/dev/null 2>&1 <<OSA
tell application "Finder"
  tell disk "$volume"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Pendant.app" of container window to {170, 232}
    set position of item "Applications" of container window to {490, 232}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
then
  echo "warning: Finder did not apply the window layout (allow Terminal / Claude to control Finder); the image has no background" >&2
fi

sync
hdiutil detach "/Volumes/$volume" >/dev/null
rm -f "$output"
hdiutil convert "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$output" >/dev/null
echo "Built: $output"
