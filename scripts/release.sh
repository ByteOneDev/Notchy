#!/bin/zsh
# Builds Notchy, packages it as a DMG and a zip, and publishes a GitHub release for the
# version in VERSION.
# Usage: scripts/release.sh "Release notes in markdown"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
NOTES=${1:-"Notchy $VERSION"}
./scripts/build.sh

ZIP="build/Notchy-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Notchy.app "$ZIP"

# DMG: the app next to a shortcut to Applications, to install by drag and drop.
DMG="build/Notchy-$VERSION.dmg"
STAGING="build/dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto build/Notchy.app "$STAGING/Notchy.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Notchy $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"
IDENTITY=$(codesign -dv build/Notchy.app 2>&1 | sed -n 's/^Authority=//p' | head -1)
[[ -n "$IDENTITY" ]] && codesign --force --sign "$IDENTITY" --timestamp "$DMG"

# Check what is about to be published.
[[ "$(plutil -extract CFBundleShortVersionString raw build/Notchy.app/Contents/Info.plist)" == "$VERSION" ]]
hdiutil verify "$DMG" >/dev/null

# Checksums, to check a download against what was published.
SUMS="build/Notchy-$VERSION-SHA256.txt"
(cd build && shasum -a 256 "Notchy-$VERSION.dmg" "Notchy-$VERSION.zip") > "$SUMS"
NOTES="$NOTES

**SHA-256**
\`\`\`
$(cat "$SUMS")
\`\`\`"

git tag -f "v$VERSION"
# Push over HTTPS with the gh credentials (works without an SSH key).
git -c credential.helper= -c credential.helper="!gh auth git-credential" push --force https://github.com/ByteOneDev/Notchy.git "v$VERSION"
gh release create "v$VERSION" "$DMG" "$ZIP" "$SUMS" --repo ByteOneDev/Notchy --title "Notchy $VERSION" --notes "$NOTES" --latest
