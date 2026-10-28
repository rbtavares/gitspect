#!/bin/sh
# Builds a release binary and wraps it in GitSpect.app.
set -eu
cd "$(dirname "$0")"
swift build -c release
APP=GitSpect.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/GitSpect" "$APP/Contents/MacOS/GitSpect"
# Icon: rendered by scripts/make-icon.swift; delete Assets/AppIcon.icns to regenerate.
if [ ! -f Assets/AppIcon.icns ]; then
    ICONSET=.build/AppIcon.iconset
    rm -rf "$ICONSET" && mkdir -p "$ICONSET" Assets
    swift scripts/make-icon.swift .build/icon-1024.png
    for s in 16 32 128 256 512; do
        sips -z $s $s .build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) .build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
fi
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
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
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built $APP"
