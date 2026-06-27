#!/bin/bash
#
# build.sh — Build halfFull.app without Xcode.
#
# Compiles all Swift sources with the Command Line Tools toolchain, then assembles
# a proper .app bundle (Info.plist, icns, ad-hoc codesign). Use when you don't have
# Xcode installed — for normal development, open the .xcodeproj and ⌘R.
#
# Output: build/halfFull.app
#
# Notes:
#   • Skips the String Catalog compile step (needs actool from Xcode). At runtime,
#     NSLocalizedString falls back to the inline `value:` parameter (English).
#   • Ad-hoc signs the bundle so it can launch locally. For redistribution you
#     still need to notarize from a real Xcode + Developer ID setup.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="build"
APP_DIR="$BUILD_DIR/halfFull.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "▸ Cleaning previous build…"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

echo "▸ Compiling Swift sources…"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_SOURCES=(
    AccessibilityHelper.swift
    AXTextEditor.swift
    ConversionController.swift
    ConversionEngine.swift
    FocusInspector.swift
    halfFullApp.swift
    HotKeyManager.swift
    HotKeyRecorderView.swift
    KeyboardSimulator.swift
    KeyCode.swift
    LaunchAtLoginManager.swift
    MainView.swift
    NotificationPresenter.swift
    PasteboardArbiter.swift
    PreferencesStore.swift
    StatusBarController.swift
    WindowControllers.swift
)
# Universal build: compile separately for arm64 and x86_64, then lipo-merge.
# (swiftc can't emit a multi-arch Mach-O directly; the canonical pattern is
# one swiftc invocation per arch, then `lipo -create`.) Intel Macs are still
# a meaningful slice of macOS 13+ users — shipping arm64-only without a clear
# "Apple silicon only" notice would silently break their download.
COMMON_FLAGS=( -O -sdk "$SDK"
    -framework AppKit -framework SwiftUI -framework Carbon
    -framework UserNotifications -framework ServiceManagement
    -module-name halfFull )

swiftc "${COMMON_FLAGS[@]}" \
    -target arm64-apple-macos13.0 \
    -o "$MACOS/halfFull-arm64" \
    "${SWIFT_SOURCES[@]}"

swiftc "${COMMON_FLAGS[@]}" \
    -target x86_64-apple-macos13.0 \
    -o "$MACOS/halfFull-x86_64" \
    "${SWIFT_SOURCES[@]}"

lipo -create "$MACOS/halfFull-arm64" "$MACOS/halfFull-x86_64" \
    -output "$MACOS/halfFull"
rm "$MACOS/halfFull-arm64" "$MACOS/halfFull-x86_64"

echo "▸ Writing Info.plist (with CFBundleIconFile=AppIcon for runtime icon lookup)…"
# CFBundleIconName requires the asset catalog compiled by actool. Without actool we
# fall back to the legacy CFBundleIconFile + .icns in Resources/. The runtime accepts
# either; we use the legacy path here so the icon shows up in Dock/Finder.
sed -e 's/<key>CFBundleIconName<\/key>/<key>CFBundleIconFile<\/key>/' \
    -e 's/<string>AppIcon<\/string>/<string>AppIcon<\/string>/' \
    -e 's|\$(EXECUTABLE_NAME)|halfFull|g' \
    -e 's|\$(PRODUCT_BUNDLE_IDENTIFIER)|me.taresky.halffull|g' \
    -e 's|\$(PRODUCT_NAME)|halfFull|g' \
    -e 's|\$(MACOSX_DEPLOYMENT_TARGET)|13.0|g' \
    Info.plist > "$CONTENTS/Info.plist"

# Required marker file: tells launchd this is an app, not a plain bundle.
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "▸ Building AppIcon.icns from the .appiconset…"
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
# iconutil expects this exact filename convention.
APPICONSET="Assets.xcassets/AppIcon.appiconset"
cp "$APPICONSET/icon_16x16@1x.png"   "$ICONSET/icon_16x16.png"
cp "$APPICONSET/icon_16x16@2x.png"   "$ICONSET/icon_16x16@2x.png"
cp "$APPICONSET/icon_32x32@1x.png"   "$ICONSET/icon_32x32.png"
cp "$APPICONSET/icon_32x32@2x.png"   "$ICONSET/icon_32x32@2x.png"
cp "$APPICONSET/icon_128x128@1x.png" "$ICONSET/icon_128x128.png"
cp "$APPICONSET/icon_128x128@2x.png" "$ICONSET/icon_128x128@2x.png"
cp "$APPICONSET/icon_256x256@1x.png" "$ICONSET/icon_256x256.png"
cp "$APPICONSET/icon_256x256@2x.png" "$ICONSET/icon_256x256@2x.png"
cp "$APPICONSET/icon_512x512@1x.png" "$ICONSET/icon_512x512.png"
cp "$APPICONSET/icon_512x512@2x.png" "$ICONSET/icon_512x512@2x.png"
iconutil --convert icns "$ICONSET" --output "$RESOURCES/AppIcon.icns"
rm -rf "$ICONSET"

echo "▸ Copying String Catalog source (English-only runtime; localized at Xcode build time)…"
cp Localizable.xcstrings "$RESOURCES/" || true

echo "▸ Re-copying bundle via ditto to strip Finder/resource detritus…"
# macOS attaches `com.apple.FinderInfo` to anything it touches in Finder, and
# `com.apple.provenance` to bash-written files. codesign rejects both with
# "resource fork, Finder information, or similar detritus not allowed."
# Standard mitigation: ditto copy with --norsrc --noextattr --noacl, then sign.
CLEAN_APP="$BUILD_DIR/.clean/halfFull.app"
rm -rf "$BUILD_DIR/.clean"
mkdir -p "$BUILD_DIR/.clean"
ditto --norsrc --noextattr --noacl "$APP_DIR" "$CLEAN_APP"
rm -rf "$APP_DIR"
mv "$CLEAN_APP" "$APP_DIR"
rmdir "$BUILD_DIR/.clean" 2>/dev/null || true

echo "▸ Ad-hoc codesigning…"
# The hardened runtime is enabled in the Xcode project too; mirror it here.
codesign \
    --sign - \
    --force \
    --deep \
    --options runtime \
    --entitlements halfFull.entitlements \
    "$APP_DIR"

echo
echo "✓ Built $APP_DIR"
echo
codesign --verify --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/  /'
echo
echo "Install with:   cp -R \"$APP_DIR\" /Applications/"
echo "Launch with:    open \"$APP_DIR\""
