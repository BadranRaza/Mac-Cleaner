#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
cd "$PROJECT_ROOT"

CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release)
    ;;
  *)
    echo "Usage: $0 [debug|release]"
    exit 1
    ;;
esac

SWIFTPM_CACHE_DIR="/tmp/swifttmp"
CLANG_CACHE_DIR="/tmp/clang-cache"

stop_existing_app() {
  if ! pgrep -x "MacCleanerGUI" >/dev/null 2>&1; then
    return
  fi

  echo "Stopping existing MacCleanerGUI processes..."
  pkill -TERM -x "MacCleanerGUI" || true

  for _ in {1..20}; do
    if ! pgrep -x "MacCleanerGUI" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done

  echo "Force-stopping stubborn MacCleanerGUI processes..."
  pkill -KILL -x "MacCleanerGUI" || true
}

stop_existing_app

echo "Building MacCleanerGUI ($CONFIG)..."
SWIFTPM_CACHE_DIR="$SWIFTPM_CACHE_DIR" \
CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" \
SWIFT_MODULE_CACHE_PATH="$SWIFTPM_CACHE_DIR" \
swift build --product MacCleanerGUI -c "$CONFIG"

if [[ "$CONFIG" == "release" ]]; then
  EXECUTABLE_PATH=".build/release/MacCleanerGUI"
  APP_PATH=".build/MacCleanerGUI.app"
else
  EXECUTABLE_PATH=".build/debug/MacCleanerGUI"
  APP_PATH=".build/MacCleanerGUI.app"
fi

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Build artifact not found at $EXECUTABLE_PATH"
  exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cat > "$APP_PATH/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleDisplayName</key>
    <string>Mac Cleaner</string>
    <key>CFBundleExecutable</key>
    <string>MacCleanerGUI</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.maccleaner.gui</string>
    <key>CFBundleName</key>
    <string>Mac Cleaner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
  </dict>
</plist>
EOF

cp "$EXECUTABLE_PATH" "$APP_PATH/Contents/MacOS/MacCleanerGUI"
chmod +x "$APP_PATH/Contents/MacOS/MacCleanerGUI"

echo "Opening $APP_PATH"
open -n "$APP_PATH"
