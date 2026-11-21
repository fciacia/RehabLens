#!/bin/sh
# Fix iOS codesign "resource fork, Finder information, or similar detritus not allowed".
# Run from project root: ./scripts/ios_clean_build.sh [device_id]
# Or: bash scripts/ios_clean_build.sh
set -e
cd "$(dirname "$0")/.."

echo "Cleaning Flutter build..."
flutter clean

echo "Clearing extended attributes from Flutter engine cache..."
if [ -n "$FLUTTER_ROOT" ]; then
  xattr -cr "$FLUTTER_ROOT/bin/cache/artifacts/engine" 2>/dev/null || true
else
  xattr -cr "$(which flutter | xargs dirname | xargs dirname)/bin/cache/artifacts/engine" 2>/dev/null || true
fi

echo "Clearing extended attributes from project..."
xattr -cr . 2>/dev/null || true

echo "Running flutter run (set COPYFILE_DISABLE=1 to avoid new xattrs)..."
export COPYFILE_DISABLE=1
if [ -n "$1" ]; then
  flutter run -d "$1"
else
  flutter run
fi
