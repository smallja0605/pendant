#!/bin/bash
# Builds Pendant and installs it into /Applications (replacing the old copy), then opens it.
# Usage: scripts/install.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-release.sh "$@"
osascript -e 'tell application "Pendant" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/Pendant.app
ditto build.noindex/Build/Products/Release/Pendant.app /Applications/Pendant.app
open /Applications/Pendant.app
echo "Installed to /Applications/Pendant.app"
