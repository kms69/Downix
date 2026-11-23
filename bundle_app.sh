#!/bin/bash
# Build and bundle DownloadManager.app

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="DownloadManager"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

# The newest CommandLineTools SDK (27.x) references SwiftUIMacros for @State but
# ships no macro plugin, so clean builds fail. Pin the 26.x SDK when present.
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
fi

echo "🔨 Building..."
CONFIG="${CONFIG:-debug}"
CONFIG_CAP="$(echo "${CONFIG:0:1}" | tr a-z A-Z)${CONFIG:1}"
swift build -c "$CONFIG"
echo "✅ Build complete"

# Locate the built executable (layout differs between toolchains).
EXECUTABLE=""
for candidate in \
    "$SCRIPT_DIR/.build/out/Products/$CONFIG_CAP/$APP_NAME" \
    "$SCRIPT_DIR/.build/arm64-apple-macosx/$CONFIG/$APP_NAME" \
    "$SCRIPT_DIR/.build/$CONFIG/$APP_NAME"; do
    if [ -f "$candidate" ]; then EXECUTABLE="$candidate"; break; fi
done
if [ -z "$EXECUTABLE" ]; then
    EXECUTABLE="$(find "$SCRIPT_DIR/.build" -name "$APP_NAME" -type f -perm -111 2>/dev/null | head -n 1)"
fi
if [ -z "$EXECUTABLE" ]; then
    echo "❌ Could not locate built executable"
    exit 1
fi

# Create .app structure
echo "📦 Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Write Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.downloadmanager.app</string>
    <key>CFBundleName</key>
    <string>Downix</string>
    <key>CFBundleDisplayName</key>
    <string>Downix</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>DownloadManager</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.downloadmanager.app.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>downloadmanager</string>
            </array>
        </dict>
    </array>
    <key>NSAppleEventsUsageDescription</key>
    <string>Download Manager asks System Events to put your Mac to sleep or shut it down when your downloads finish.</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
PLIST

# Downix app icon (.icns built from Branding/AppIcon-1024.png)
ICON_SRC="$SCRIPT_DIR/Branding/AppIcon-1024.png"
if [ -f "$ICON_SRC" ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" && echo "✅ App icon created"
fi

# Downix logo images (frame-less colour mark + white menu-bar mask)
for f in DownixMark.png DownixMenu.png; do
    if [ -f "$SCRIPT_DIR/Branding/$f" ]; then cp "$SCRIPT_DIR/Branding/$f" "$APP_BUNDLE/Contents/Resources/$f"; fi
done

echo "✅ .app bundle created at: $APP_BUNDLE"

# Register the app with macOS Launch Services so the downloadmanager:// URL scheme
# is recognized system-wide (needed for browser extension integration).
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP_BUNDLE" 2>/dev/null && echo "✅ URL scheme registered with Launch Services"
fi

echo ""
echo "🚀 To run:  open '$APP_BUNDLE'"
echo "   Or:      '$APP_BUNDLE/Contents/MacOS/$APP_NAME'"
