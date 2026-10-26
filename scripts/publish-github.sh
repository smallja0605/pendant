#!/bin/bash
# Publishes what `scripts/prepare-daily-release.sh` prepared: commits the working tree as "Release X.Y.Z", tags it, pushes the
# branch and the tag to GitHub and creates the GitHub release with the disk image and its SHA-256 file. Run it ONLY after the developer
# has confirmed. The installed app and the local update folder are not touched.
# Usage: scripts/publish-github.sh X.Y.Z [--force-with-lease]   (the flag: the first push after the local history was rewritten)
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/publish-github.sh X.Y.Z [--force-with-lease]}"
out=build.noindex/release
for file in "$out/Pendant-$version.dmg" "$out/Pendant-$version.dmg.sha256" "$out/Pendant-$version.dmg.sig" "$out/notes-$version.md"; do
  [ -f "$file" ] || { echo "missing $file: run scripts/prepare-daily-release.sh first" >&2; exit 1; }
done
grep -q "MARKETING_VERSION = $version;" Pendant.xcodeproj/project.pbxproj || { echo "project version is not $version" >&2; exit 1; }

# A secret scan before anything leaves the machine.
gitleaks detect --no-banner --redact >/dev/null 2>&1 || { echo "gitleaks found something: not publishing" >&2; exit 1; }

git add -A
git commit -q -m "Release $version" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" || true
git tag -f "v$version" >/dev/null
if [ "${2:-}" = "--force-with-lease" ]; then
  git push --force-with-lease origin main
else
  git push origin main
fi
git push origin "v$version"
gh release create "v$version" "$out/Pendant-$version.dmg" "$out/Pendant-$version.dmg.sha256" "$out/Pendant-$version.dmg.sig" \
  --repo smallja0605/pendant --title "Pendant $version" --notes-file "$out/notes-$version.md"
echo "Published v$version"
