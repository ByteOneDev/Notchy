#!/bin/zsh
# Builds build/Notchy.app (release) and signs it.
# NOTCHY_SIGN_IDENTITY: code signing identity. A stable identity keeps the macOS permissions
# (Accessibility, camera, calendar…) across updates; "-" signs ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

# Fall back to the Command Line Tools when Xcode is unusable (e.g. license not accepted).
if ! xcrun --find swift >/dev/null 2>&1 || ! xcrun swift --version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

VERSION=$(cat VERSION)
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
IDENTITY=${NOTCHY_SIGN_IDENTITY:-}
if [[ -z "$IDENTITY" ]]; then
  if security find-identity -v -p codesigning | grep -q "Todoux Developer"; then
    IDENTITY="Todoux Developer"
  else
    IDENTITY="-"
  fi
fi
# Real identity: secure timestamp from Apple and hardened runtime. Ad hoc can't have either.
SIGN_FLAGS=()
[[ "$IDENTITY" != "-" ]] && SIGN_FLAGS=(--timestamp --options runtime)

swift build -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)

APP=build/Notchy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Notchy" "$APP/Contents/MacOS/Notchy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/fr.lproj "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Media adapter: loaded by /usr/bin/perl to reach MediaRemote (see MediaAdapter/NotchyMediaAdapter.m).
mkdir -p "$APP/Contents/Resources/MediaAdapter"
clang -fobjc-arc -O2 -dynamiclib -arch arm64 -mmacosx-version-min=15.0 -framework Foundation \
  -o "$APP/Contents/Resources/MediaAdapter/NotchyMediaAdapter.dylib" MediaAdapter/NotchyMediaAdapter.m
cp MediaAdapter/run.pl "$APP/Contents/Resources/MediaAdapter/run.pl"
codesign --force --sign "$IDENTITY" "${SIGN_FLAGS[@]}" "$APP/Contents/Resources/MediaAdapter/NotchyMediaAdapter.dylib"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

codesign --force --sign "$IDENTITY" "${SIGN_FLAGS[@]}" --entitlements Resources/Notchy.entitlements "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP $VERSION ($BUILD_NUMBER), signed with: $IDENTITY"
