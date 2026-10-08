#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$ROOT_DIR/Resources"
ICONSET="$RESOURCES/AppIcon.iconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  printf '%s\n' 'Icon generation requires rsvg-convert (Homebrew: brew install librsvg).' >&2
  exit 1
fi

mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  rsvg-convert --width "$size" --height "$size" "$RESOURCES/AppIcon.svg" \
    --output "$ICONSET/icon_${size}x${size}.png"
  rsvg-convert --width "$((size * 2))" --height "$((size * 2))" "$RESOURCES/AppIcon.svg" \
    --output "$ICONSET/icon_${size}x${size}@2x.png"
done
cp "$ICONSET/icon_512x512@2x.png" "$RESOURCES/AppIcon.png"
/usr/bin/iconutil --convert icns "$ICONSET" --output "$RESOURCES/AppIcon.icns"
printf '%s\n' 'Generated PixelFit AppIcon.png, AppIcon.iconset and AppIcon.icns.'
