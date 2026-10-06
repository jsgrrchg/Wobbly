#!/usr/bin/env bash
# Copyright (C) 2026 José Gurruchaga
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds and packages build/Wobbly.app as a universal binary (Apple Silicon and Intel).
# Signs with the "Apple Development" identity if one exists (or SIGN_IDENTITY): with a stable signature
# macOS keeps the Accessibility and Screen Recording permissions across builds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" "${ARCHS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)"

APP="build/Wobbly.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Wobbly" "$APP/Contents/MacOS/Wobbly"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Icon Composer icon: actool generates Assets.car (Liquid Glass) and a fallback Wobbly.icns.
xcrun actool Resources/Wobbly.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon Wobbly \
    --output-partial-info-plist "$(mktemp -t wobbly-icon)" > /dev/null

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc}"
echo "$APP"
