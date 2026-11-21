#!/usr/bin/env bash
# Fetches Firestore/Protos/nanopb from firebase-ios-sdk and extracts to ios/patches/Protos_nanopb.
# Run once if the FirebaseFirestoreInternal pod is missing these headers (e.g. document.nanopb.h).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$(cd "$SCRIPT_DIR/../patches" && pwd)"
DEST="$PATCHES_DIR/Protos_nanopb"
SDK_VERSION="${1:-11.15.0}"
ZIP_URL="https://github.com/firebase/firebase-ios-sdk/archive/refs/tags/${SDK_VERSION}.zip"
EXTRACT_DIR="$PATCHES_DIR/firebase-ios-sdk-${SDK_VERSION}"

if [ -d "$DEST" ] && [ -f "$DEST/google/firestore/v1/document.nanopb.h" ]; then
  echo "Protos_nanopb already present at $DEST"
  exit 0
fi

echo "Downloading firebase-ios-sdk ${SDK_VERSION}..."
curl -sL -o "$PATCHES_DIR/sdk.zip" "$ZIP_URL"
echo "Extracting Firestore/Protos/nanopb..."
mkdir -p "$PATCHES_DIR"
unzip -o -q "$PATCHES_DIR/sdk.zip" "firebase-ios-sdk-${SDK_VERSION}/Firestore/Protos/nanopb/*" -d "$PATCHES_DIR"
rm -rf "$DEST"
mv "$PATCHES_DIR/firebase-ios-sdk-${SDK_VERSION}/Firestore/Protos/nanopb" "$DEST"
rm -rf "$EXTRACT_DIR" "$PATCHES_DIR/sdk.zip"
echo "Done. Protos_nanopb at $DEST"
exit 0
