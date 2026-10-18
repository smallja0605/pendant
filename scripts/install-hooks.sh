#!/bin/sh
set -e
git rev-parse --git-dir >/dev/null
cp scripts/pre-commit "$(git rev-parse --git-path hooks)/pre-commit"
chmod +x "$(git rev-parse --git-path hooks)/pre-commit"
echo "pre-commit hook installed"
