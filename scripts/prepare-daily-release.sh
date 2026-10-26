#!/bin/bash
# Prepares the day's GitHub release WITHOUT publishing anything: bumps the version once, moves the [Unreleased] changelog entries
# under it, builds the ad-hoc signed app and packs it into a disk image with a SHA-256 file into build.noindex/release/. Nothing is committed, pushed
# or uploaded and the installed app / the local update folder are not touched; `scripts/publish-github.sh X.Y.Z` does that after
# the developer has confirmed.
# Usage: scripts/prepare-daily-release.sh [--force | --rebuild]
#   --force:   release even when [Unreleased] is empty
#   --rebuild: rebuild the already prepared, not yet published version from the current tree (a fix went in after preparing it)
# Prints one of: READY <version> | SKIP <reason>
set -euo pipefail
cd "$(dirname "$0")/.."

force=0
rebuild=0
[ "${1:-}" = "--force" ] && force=1
[ "${1:-}" = "--rebuild" ] && rebuild=1
out=build.noindex/release
mkdir -p "$out"

today=$(date +%Y-%m-%d)
current=$(grep -m1 "MARKETING_VERSION" Pendant.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/')
latest=$(gh release list --repo smallja0605/pendant --limit 1 --json tagName,createdAt -q '.[0] | "\(.tagName) \(.createdAt)"' 2>/dev/null || true)
latest_tag=${latest%% *}
latest_day=$(python3 -c "
import sys, datetime
s = sys.argv[1].split(' ')[-1]
if not s.endswith('Z'): print(''); sys.exit()
d = datetime.datetime.fromisoformat(s.replace('Z', '+00:00')).astimezone()
print(d.strftime('%Y-%m-%d'))" "${latest:-none}")

if [ "$rebuild" = 1 ]; then
  gh release view "v$current" --repo smallja0605/pendant >/dev/null 2>&1 && { echo "SKIP v$current is already published"; exit 0; }
  notes=$(python3 - "$current" <<'PY'
import re, sys
text = open("CHANGELOG.md", encoding="utf-8").read()
m = re.search(r"## \[%s\][^\n]*\n(.*?)(?=\n## \[)" % re.escape(sys.argv[1]), text, re.S)
print((m.group(1) if m else "").strip())
PY
)
  scripts/build-release.sh "$current" >/dev/null
  rm -f "$out"/Pendant-*.dmg "$out"/Pendant-*.dmg.sha256 "$out"/Pendant-*.dmg.sig "$out"/notes-*.md
  scripts/make-dmg.sh build.noindex/Build/Products/Release/Pendant.app "$out/Pendant-$current.dmg" >/dev/null
  (cd "$out" && shasum -a 256 "Pendant-$current.dmg" > "Pendant-$current.dmg.sha256")
  swift scripts/update-signing.swift sign "$current" "$out/Pendant-$current.dmg" >/dev/null
  printf '%s\n' "$notes" > "$out/notes-$current.md"
  echo "READY $current (rebuilt)"
  echo "notes: $out/notes-$current.md"
  exit 0
fi

# Already prepared and still waiting for the developer's confirmation (e.g. the midnight run, now the 17:00 reminder): reuse it.
if [ -f "$out/Pendant-$current.dmg" ] && ! gh release view "v$current" --repo smallja0605/pendant >/dev/null 2>&1; then
  echo "READY $current (already prepared, not yet published)"
  echo "notes: $out/notes-$current.md"
  exit 0
fi

# One release per day: a release created today (local time) means today is done.
if [ -n "$latest_day" ] && [ "$latest_day" = "$today" ] && [ "$force" = 0 ]; then
  echo "SKIP already released today ($latest_tag)"; exit 0
fi

# Next version = the higher of the project's and the newest release's, patch + 1 (0.4.14 -> 0.4.15).
version=$(python3 - "$current" "${latest_tag#v}" <<'PY'
import sys
def parse(v):
    try:
        a, b, c = v.split("-")[0].split(".")
        return (int(a), int(b), int(c))
    except Exception:
        return (0, 0, 0)
top = max(parse(sys.argv[1]), parse(sys.argv[2]))
print("%d.%d.%d" % (top[0], top[1], top[2] + 1))
PY
)

# The day's changes: the [Unreleased] section of CHANGELOG.md.
notes=$(python3 - <<'PY'
import re
text = open("CHANGELOG.md", encoding="utf-8").read()
m = re.search(r"## \[Unreleased\]\n(.*?)(?=\n## \[)", text, re.S)
print((m.group(1) if m else "").strip())
PY
)
if [ -z "$notes" ] && [ "$force" = 0 ]; then
  echo "SKIP no changes since the last release ([Unreleased] is empty)"; exit 0
fi
[ -z "$notes" ] && notes="### Changed
- 例行更新。"

python3 - "$version" "$today" <<'PY'
import re, sys
version, day = sys.argv[1:3]
text = open("CHANGELOG.md", encoding="utf-8").read()
if "## [Unreleased]\n\n## [" in text:
    text = text.replace("## [Unreleased]\n", "## [Unreleased]\n\n## [%s] - %s\n\n### Changed\n- 例行更新。\n" % (version, day), 1)
else:
    text = text.replace("## [Unreleased]\n", "## [Unreleased]\n\n## [%s] - %s\n" % (version, day), 1)
open("CHANGELOG.md", "w", encoding="utf-8").write(text)
PY
sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $version;/" Pendant.xcodeproj/project.pbxproj

scripts/build-release.sh "$version" >/dev/null
rm -f "$out"/Pendant-*.dmg "$out"/Pendant-*.dmg.sha256 "$out"/Pendant-*.dmg.sig "$out"/notes-*.md
scripts/make-dmg.sh build.noindex/Build/Products/Release/Pendant.app "$out/Pendant-$version.dmg" >/dev/null
(cd "$out" && shasum -a 256 "Pendant-$version.dmg" > "Pendant-$version.dmg.sha256")
swift scripts/update-signing.swift sign "$version" "$out/Pendant-$version.dmg" >/dev/null
printf '%s\n' "$notes" > "$out/notes-$version.md"
echo "READY $version"
echo "notes: $out/notes-$version.md"
