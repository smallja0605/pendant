#!/bin/bash
# Publishes a new version for the installed app's in-app updater (no network, no GitHub):
# builds it, zips it with a SHA-256 file into ~/Library/Application Support/Pendant/Updates and rewrites releases.json.
# The installed Pendant finds it on its next check ("設定 → 關於 → 檢查更新") and replaces itself.
# Usage: scripts/publish-update.sh <version>     e.g. 0.1.1 (stable) or 0.1.2-beta.1 (test build: only offered on the
# "含預覽版" update channel in 設定 → 關於)
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/publish-update.sh <version>  (e.g. 0.1.1)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "version must look like 1.2.3 or 1.2.3-beta.1" >&2; exit 1; }

scripts/build-release.sh "$version"
folder="$HOME/Library/Application Support/Pendant/Updates"
mkdir -p "$folder"
zip="Pendant-$version.zip"
ditto -c -k --keepParent build.noindex/Build/Products/Release/Pendant.app "$folder/$zip"
(cd "$folder" && shasum -a 256 "$zip" > "$zip.sha256")
swift scripts/update-signing.swift sign "$version" "$folder/$zip" >/dev/null

python3 - "$folder" <<'PY'
import json, os, re, sys
folder = sys.argv[1]
releases = []
for name in sorted(os.listdir(folder)):
    m = re.fullmatch(r"Pendant-(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)\.zip", name)
    if not m:
        continue
    assets = []
    for asset in (name, name + ".sha256", name + ".sig"):
        path = os.path.join(folder, asset)
        if not os.path.exists(path):
            continue
        assets.append({"name": asset, "browser_download_url": "file://" + path, "size": os.path.getsize(path)})
    releases.append({"tag_name": "v" + m.group(1), "name": "Pendant " + m.group(1),
                     "prerelease": "-" in m.group(1), "draft": False, "body": "", "assets": assets})
with open(os.path.join(folder, "releases.json"), "w") as out:
    json.dump(releases, out, indent=2)
PY
echo "Published $version to $folder"
