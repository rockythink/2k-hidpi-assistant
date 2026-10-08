#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PixelFit"
APP_VERSION="0.2.0"
APP_BUILD="2"
BUNDLE_ID="cc.ss-data.hidpibuddy"
MIN_SYSTEM_VERSION="14.0"
HELPER_NAME="PixelFitVirtualDisplayHelper"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"

cd "$ROOT_DIR"
if [[ "$MODE" == "--release" ]]; then
  # Release is build-only and requires an explicitly selected, valid Developer ID.
  if [[ -z "${SIGN_IDENTITY:-}" || "$SIGN_IDENTITY" != "Developer ID Application: "* ]]; then
    echo "--release requires SIGN_IDENTITY to be a full valid Developer ID Application identity name." >&2
    exit 1
  fi
  if ! SIGNING_IDENTITIES="$(security find-identity -v -p codesigning)"; then
    echo "Unable to enumerate valid signing identities; refusing to build a release." >&2
    exit 1
  fi
  RELEASE_SIGN_HASH=""
  IDENTITY_PATTERN='^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"([^"]+)"[[:space:]]*$'
  while IFS= read -r identity; do
    if [[ "$identity" =~ $IDENTITY_PATTERN && "${BASH_REMATCH[2]}" == "$SIGN_IDENTITY" ]]; then
      if [[ -n "$RELEASE_SIGN_HASH" ]]; then
        echo "SIGN_IDENTITY matches multiple valid identities; refusing ambiguous release signing." >&2
        exit 1
      fi
      RELEASE_SIGN_HASH="${BASH_REMATCH[1]}"
    fi
  done <<< "$SIGNING_IDENTITIES"
  if [[ -z "$RELEASE_SIGN_HASH" ]]; then
    echo "SIGN_IDENTITY does not exactly match a valid Developer ID Application identity." >&2
    exit 1
  fi
elif [[ "$MODE" != "--build" && "$MODE" != "build" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

if [[ "$MODE" == "--release" ]]; then
  swift build -c release --arch arm64
  BUILD_BINARY="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
else
  swift build
  BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$(dirname "$BUILD_BINARY")/$HELPER_NAME" "$APP_MACOS/$HELPER_NAME"
chmod +x "$APP_BINARY" "$APP_MACOS/$HELPER_NAME"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
  <key>NSSupportsSuddenTermination</key>
  <false/>
</dict>
</plist>
PLIST

if [[ "$MODE" == "--release" ]]; then
  # Sign inside-out, without --deep; only verification traverses nested code.
  codesign --force --options runtime --timestamp --sign "$RELEASE_SIGN_HASH" \
    --identifier "$BUNDLE_ID.virtual-display-helper" "$APP_MACOS/$HELPER_NAME"
  codesign --force --options runtime --timestamp --sign "$RELEASE_SIGN_HASH" \
    --identifier "$BUNDLE_ID" "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F\" '/"/ { print $2; exit }')"
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
  else
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
  fi
fi

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

case "$MODE" in
  --build|build|--release)
    printf "%s\n" "$APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build|--release|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
