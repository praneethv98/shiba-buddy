#!/bin/zsh
# Builds ShibaBuddy.app next to this script.
set -e
cd "$(dirname "$0")"
APP=ShibaBuddy.app
BIN=ShibaBuddy
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -module-cache-path "${TMPDIR:-/tmp}/shiba-buddy-module-cache" *.swift -o "$APP/Contents/MacOS/$BIN" -framework AppKit -framework ServiceManagement

# App icon, rendered from the pixel art itself
ICONSET="${TMPDIR:-/tmp}/ShibaBuddy.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/$BIN" --iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Shiba Buddy</string>
  <key>CFBundleDisplayName</key><string>Shiba Buddy</string>
  <key>CFBundleIdentifier</key><string>local.shibabuddy</string>
  <key>CFBundleExecutable</key><string>ShibaBuddy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
</dict></plist>
EOF

# Sign with a stable identity so macOS remembers Accessibility / Screen Recording
# permissions across rebuilds (ad-hoc signatures change every build).
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --timestamp=none -s "$SIGN_ID" "$APP"
else
  codesign --force -s - "$APP"
  echo "warning: no signing identity found; ad-hoc signed, so permissions may reset after each rebuild"
fi
codesign --verify --strict "$APP"
echo "Built $PWD/$APP (signed: ${SIGN_ID:-ad-hoc})"
