#!/bin/bash
# Builds an ad-hoc signed Release build of Pendant.app into build/Build/Products/Release.
# Usage: scripts/build-release.sh [version]   (default: the version in the Xcode project)
set -euo pipefail
cd "$(dirname "$0")/.."

args=(-project Pendant.xcodeproj -scheme Pendant -configuration Release -derivedDataPath build)
[ $# -ge 1 ] && args+=(MARKETING_VERSION="$1")
xcodebuild "${args[@]}" build | tail -3
codesign --verify --deep --strict build/Build/Products/Release/Pendant.app
echo "Built: build/Build/Products/Release/Pendant.app"
