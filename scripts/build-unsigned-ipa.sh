#!/usr/bin/env bash
# Compiles on GitHub's macOS hosted runner. No code-signing credentials are used.
# The resulting IPA must be signed on Windows by a local installer (e.g. Sideloadly).
set -euo pipefail

PROJECT='iPhone/iPhoneBLECamera.xcodeproj'
DERIVED_DATA="$PWD/.ios-derived-data"
OUTPUT="$PWD/output"
APP="$DERIVED_DATA/Build/Products/Release-iphoneos/iPhoneBLECamera.app"

mkdir -p "$OUTPUT"
xcodebuild \
  -project "$PROJECT" \
  -scheme 'iPhoneBLECamera' \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tee "$OUTPUT/xcodebuild.log"

if [[ ! -d "$APP" || ! -f "$APP/Info.plist" ]]; then
  echo 'ERROR: iPhone app bundle was not generated.' >&2
  exit 1
fi

rm -rf "$OUTPUT/Payload"
mkdir -p "$OUTPUT/Payload"
ditto "$APP" "$OUTPUT/Payload/iPhoneBLECamera.app"
(
  cd "$OUTPUT"
  zip -q -r 'iPhoneBLECamera-unsigned.ipa' Payload
  unzip -t 'iPhoneBLECamera-unsigned.ipa' >/dev/null
  rm -rf Payload
)

echo "Unsigned IPA created: $OUTPUT/iPhoneBLECamera-unsigned.ipa"
