#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="objectbox_viewer"
OUTPUT_DIR="dist"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

APP_PATH="$ROOT_DIR/build/macos/Build/Products/Release/$APP_NAME.app"
OUTPUT_PATH="$ROOT_DIR/$OUTPUT_DIR"

die() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

pubspec_version() {
  local raw
  raw="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
  raw="${raw%%+*}"
  if [[ -z "$raw" ]]; then
    raw="0.0.0"
  fi
  printf '%s' "$raw"
}

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

[[ -f "$ROOT_DIR/pubspec.yaml" ]] || die "pubspec.yaml not found; run this from a Flutter project"
[[ -d "$ROOT_DIR/macos" ]] || die "macos directory not found; this project has no macOS target"

[[ -n "$SIGN_IDENTITY" ]] || die "SIGN_IDENTITY is required"
[[ -n "$APPLE_ID" ]] || die "APPLE_ID is required"
[[ -n "$APPLE_TEAM_ID" ]] || die "APPLE_TEAM_ID is required"
[[ -n "$APPLE_APP_PASSWORD" ]] || die "APPLE_APP_PASSWORD is required"

require_cmd "$FLUTTER_BIN"
require_cmd hdiutil
require_cmd ditto
require_cmd codesign
require_cmd xcrun

VERSION="$(pubspec_version)"
DMG_NAME="$APP_NAME-$VERSION-signed.dmg"
DMG_PATH="$OUTPUT_PATH/$DMG_NAME"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}_signed_dmg.XXXXXX")"
STAGING_DIR="$TMP_DIR/staging"

echo "Project: $ROOT_DIR"
echo "App:     $APP_NAME"
echo "Version: $VERSION"
echo "Output:  $DMG_PATH"

cd "$ROOT_DIR"

echo "Running flutter pub get..."
"$FLUTTER_BIN" pub get

echo "Building macOS release app..."
"$FLUTTER_BIN" build macos --release

[[ -d "$APP_PATH" ]] || die "release app not found: $APP_PATH"

mkdir -p "$STAGING_DIR" "$OUTPUT_PATH"

echo "Preparing signed DMG staging directory..."
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Signing app with identity: $SIGN_IDENTITY"
codesign --deep --force --options runtime --sign "$SIGN_IDENTITY" "$STAGING_DIR/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/$APP_NAME.app"

echo "Creating signed DMG..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "Done: $DMG_PATH"
