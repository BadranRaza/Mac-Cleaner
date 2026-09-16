#!/usr/bin/env zsh
# Builds Reclaim.app into .build/ and opens it. Usage: Scripts/run-gui-app.sh [debug|release] [--no-open]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
[[ "$CONFIG" == debug || "$CONFIG" == release ]] || { echo "Usage: $0 [debug|release] [--no-open]"; exit 1; }

pkill -x Reclaim 2>/dev/null || true
swift build --product Reclaim -c "$CONFIG"

APP=".build/Reclaim.app"
VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Reclaim" "$APP/Contents/MacOS/Reclaim"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>Reclaim</string>
  <key>CFBundleName</key><string>Reclaim</string>
  <key>CFBundleExecutable</key><string>Reclaim</string>
  <key>CFBundleIdentifier</key><string>com.autechsolutions.reclaim</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-1.0.0}</string>
  <key>CFBundleVersion</key><string>$(git rev-list --count HEAD)</string>
  <key>ReclaimGitCommit</key><string>$(git rev-parse --short HEAD)$(git diff --quiet HEAD || echo -dirty)</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# A stable signature keeps macOS privacy grants (Full Disk Access) across rebuilds.
# Ad-hoc signatures change every build, so macOS would ask again each time.
# Override with RECLAIM_SIGN_IDENTITY="Apple Development: …".
IDENTITIES="$(security find-identity -v -p codesigning)"
SIGN_ID="${RECLAIM_SIGN_IDENTITY:-$(echo "$IDENTITIES" | grep -m1 -o '"Developer ID Application[^"]*"' | tr -d '"')}"
SIGN_ID="${SIGN_ID:-$(echo "$IDENTITIES" | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"')}"
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --timestamp=none --sign "$SIGN_ID" "$APP"
else
  echo "warning: no signing identity; macOS will ask for permissions again after every build" >&2
  codesign --force --sign - "$APP"
fi

[[ "${2:-}" == "--no-open" ]] || open -n "$APP"
