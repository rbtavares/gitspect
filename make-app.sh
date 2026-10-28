#!/bin/sh
# Builds a release binary and wraps it in GitSpect.app.
#
# VERSION  marketing version (default: latest vX.Y.Z tag without the "v", or 0.0.0)
# ARCHS    architectures to build, e.g. "arm64 x86_64" for a universal app (default: this Mac's)
set -eu
cd "$(dirname "$0")"

LATEST_TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)
VERSION=${VERSION:-${LATEST_TAG#v}}
# Build number: commit count, so every build from a later commit sorts higher.
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)

ARCH_FLAGS=""
for arch in ${ARCHS:-}; do ARCH_FLAGS="$ARCH_FLAGS --arch $arch"; done
# shellcheck disable=SC2086 # ARCH_FLAGS is intentionally word-split.
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN_PATH=$(swift build -c release $ARCH_FLAGS --show-bin-path)

APP=GitSpect.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/GitSpect" "$APP/Contents/MacOS/GitSpect"
# Icons: rendered by scripts/make-icon.swift; delete Assets/ to regenerate.
# AppIcon.icns (dark) is the bundle icon; the PNGs are the styles selectable in Settings.
if [ ! -f Assets/AppIcon.icns ] || [ ! -f Assets/AppIcon-blue.png ]; then
    mkdir -p Assets
    swiftc -O scripts/make-icon.swift -o .build/make-icon
    for style in dark light blue; do
        .build/make-icon "Assets/AppIcon-$style.png" "$style"
    done
    ICONSET=.build/AppIcon.iconset
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s Assets/AppIcon-dark.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) Assets/AppIcon-dark.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
fi
cp Assets/AppIcon.icns Assets/AppIcon-*.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GitSpect</string>
    <key>CFBundleIdentifier</key><string>com.rbtavares.gitspect</string>
    <key>CFBundleExecutable</key><string>GitSpect</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 rbtavares. MIT License.</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Shown in the macOS prompts when scanning folders in these locations. -->
    <key>NSDocumentsFolderUsageDescription</key><string>GitSpect scans the folders you add for git repositories.</string>
    <key>NSDesktopFolderUsageDescription</key><string>GitSpect scans the folders you add for git repositories.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>GitSpect scans the folders you add for git repositories.</string>
</dict>
</plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built $APP $VERSION ($BUILD)"
