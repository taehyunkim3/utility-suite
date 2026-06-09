#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="WebPDrop"
APP_NAME="Utility Suite"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
VENDORED_CWEBP_DIR="$ROOT_DIR/ThirdParty/cwebp/macos-arm64"
VENDORED_LICENSE_DIR="$ROOT_DIR/ThirdParty/cwebp/licenses"
VENDORED_NOTICE="$ROOT_DIR/ThirdParty/cwebp/NOTICE.md"

cd "$ROOT_DIR"
swift build -c release --product "$PRODUCT_NAME"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/bin" "$RESOURCES_DIR/lib" "$RESOURCES_DIR/ThirdPartyLicenses/cwebp"
cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"
cp "$VENDORED_CWEBP_DIR/bin/cwebp" "$RESOURCES_DIR/bin/cwebp"
cp "$VENDORED_CWEBP_DIR/lib/"*.dylib "$RESOURCES_DIR/lib/"
cp "$VENDORED_LICENSE_DIR/"* "$RESOURCES_DIR/ThirdPartyLicenses/cwebp/"
cp "$VENDORED_NOTICE" "$RESOURCES_DIR/ThirdPartyLicenses/cwebp/NOTICE.md"
chmod 755 "$RESOURCES_DIR/bin/cwebp"
codesign --force --sign - "$RESOURCES_DIR/bin/cwebp" "$RESOURCES_DIR/lib/"*.dylib

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleExecutable</key>
    <string>WebPDrop</string>
    <key>CFBundleIdentifier</key>
    <string>com.taehyunkim.UtilitySuite</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Utility Suite</string>
    <key>CFBundleDisplayName</key>
    <string>Utility Suite</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Packaged app: $APP_DIR"
