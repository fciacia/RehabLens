#!/bin/sh
# Fix iOS codesign "resource fork, Finder information, or similar detritus not allowed"
# Run from project root: sh scripts/fix_ios_codesign.sh

set -e
echo "Clearing extended attributes from build and ios (ignore permission errors)..."
xattr -cr build 2>/dev/null || true
xattr -cr ios 2>/dev/null || true
echo "Clearing Flutter cache (engine artifacts)..."
if [ -n "$FLUTTER_ROOT" ]; then
  xattr -cr "$FLUTTER_ROOT/bin/cache/artifacts/engine" 2>/dev/null || true
fi
echo "Cleaning build..."
flutter clean
rm -rf build
echo "Getting dependencies..."
flutter pub get
echo "Done. Run: flutter run"
