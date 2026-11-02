#!/bin/zsh
# Builds Notchy, zips it and publishes a GitHub release for the version in VERSION.
# Usage: scripts/release.sh "Release notes in markdown"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
NOTES=${1:-"Notchy $VERSION"}
./scripts/build.sh

ZIP="build/Notchy-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Notchy.app "$ZIP"

git tag -f "v$VERSION"
# Push over HTTPS with the gh credentials (works without an SSH key).
git -c credential.helper= -c credential.helper="!gh auth git-credential" push --force https://github.com/ByteOneDev/Notchy.git "v$VERSION"
gh release create "v$VERSION" "$ZIP" --repo ByteOneDev/Notchy --title "Notchy $VERSION" --notes "$NOTES"
