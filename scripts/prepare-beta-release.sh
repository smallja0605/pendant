#!/bin/bash
# Prepares a BETA release WITHOUT publishing anything. Versions follow semver pre-releases: the next stable version plus
# `-beta.N` (stable 0.4.19 -> 0.4.20-beta.1, 0.4.20-beta.2, ...; the stable 0.4.20 that follows is the plain release). The
# changelog is left alone (the [Unreleased] entries move under the stable version later). `scripts/publish-github.sh X.Y.Z-beta.N`
# publishes it as a GitHub pre-release, which only people in the testers group (設定 › 關於 › 測試者計畫) are offered.
# Usage: scripts/prepare-beta-release.sh
# Prints: READY <version>
set -euo pipefail
cd "$(dirname "$0")/.."
out=build.noindex/release
mkdir -p "$out"

tags=$(gh release list --repo smallja0605/pendant --limit 100 --json tagName -q '.[].tagName' 2>/dev/null || true)
current=$(grep -m1 "MARKETING_VERSION" Pendant.xcodeproj/project.pbxproj | sed 's/.*= \(.*\);/\1/')
version=$(python3 - "$current" $tags <<'PY'
import re, sys
def core(v):
    m = re.match(r"v?(\d+)\.(\d+)\.(\d+)", v)
    return tuple(int(x) for x in m.groups()) if m else (0, 0, 0)
current, tags = sys.argv[1], sys.argv[2:]
stable = [core(t) for t in tags if "-" not in t] + ([core(current)] if "-" not in current else [])
top = max(stable or [(0, 0, 0)])
target = (top[0], top[1], top[2] + 1)
n = 0
for t in tags + [current]:
    m = re.match(r"v?(\d+)\.(\d+)\.(\d+)-beta\.(\d+)$", t)
    if m and tuple(int(x) for x in m.groups()[:3]) == target:
        n = max(n, int(m.group(4)))
print("%d.%d.%d-beta.%d" % (*target, n + 1))
PY
)

notes=$(python3 - <<'PY'
import re
text = open("CHANGELOG.md", encoding="utf-8").read()
m = re.search(r"## \[Unreleased\]\n(.*?)(?=\n## \[)", text, re.S)
print((m.group(1) if m else "").strip())
PY
)
[ -z "$notes" ] && notes="### Changed
- 測試版。"

sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $version;/" Pendant.xcodeproj/project.pbxproj
scripts/build-release.sh "$version" >/dev/null
rm -f "$out"/Pendant-*.dmg "$out"/Pendant-*.dmg.sha256 "$out"/Pendant-*.dmg.sig "$out"/notes-*.md
scripts/make-dmg.sh build.noindex/Build/Products/Release/Pendant.app "$out/Pendant-$version.dmg" >/dev/null
(cd "$out" && shasum -a 256 "Pendant-$version.dmg" > "Pendant-$version.dmg.sha256")
swift scripts/update-signing.swift sign "$version" "$out/Pendant-$version.dmg" >/dev/null
printf '%s\n' "Beta (pre-release). Only for the testers group.

$notes" > "$out/notes-$version.md"
echo "READY $version"
echo "notes: $out/notes-$version.md"
