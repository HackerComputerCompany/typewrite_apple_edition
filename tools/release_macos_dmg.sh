#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Typewrite.xcodeproj"
SCHEME="Typewrite_macOS"
DERIVED="$ROOT/.deriveddata-macos-release"
OUTDIR="$ROOT/dist/macos"

VERSION="${VERSION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DO_NOTARIZE=0

usage() {
  cat <<'EOF'
release_macos_dmg.sh — build a downloadable macOS .dmg for Typewrite

Usage:
  tools/release_macos_dmg.sh [--version X.Y.Z] [--outdir DIR] [--notarize] [--profile NAME]

Defaults:
  - Builds scheme: Typewrite_macOS (Release)
  - Derived data: .deriveddata-macos-release/
  - Output dir:   dist/macos/
  - DMG name:     Typewrite[-VERSION].dmg

Notarization (optional):
  - Provide a notarytool keychain profile via --profile NAME (or env NOTARY_PROFILE)
  - If --notarize is set, the script will:
      1) notarize the DMG
      2) staple the ticket to the DMG

Examples:
  tools/release_macos_dmg.sh --version 0.1.0
  tools/release_macos_dmg.sh --notarize --profile notary-profile --version 0.1.0
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2;;
    --outdir) OUTDIR="${2:-}"; shift 2;;
    --notarize) DO_NOTARIZE=1; shift;;
    --profile) NOTARY_PROFILE="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ ! -d "$PROJECT" ]]; then
  echo "Missing project: $PROJECT" >&2
  exit 1
fi

mkdir -p "$OUTDIR"

echo "Building $SCHEME (Release)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" \
  -quiet \
  build

APP="$DERIVED/Build/Products/Release/Typewrite.app"
if [[ ! -d "$APP" ]]; then
  echo "Built app not found at: $APP" >&2
  exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/typewrite_dmg_stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Typewrite.app"
ln -s /Applications "$STAGE/Applications"

DMG_BASENAME="Typewrite"
if [[ -n "$VERSION" ]]; then
  DMG_BASENAME="Typewrite-$VERSION"
fi
DMG="$OUTDIR/$DMG_BASENAME.dmg"

echo "Creating DMG: $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "Typewrite" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

echo "DMG created."

if [[ "$DO_NOTARIZE" -eq 1 ]]; then
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "Notarization requested but no profile provided. Use --profile NAME or env NOTARY_PROFILE." >&2
    exit 2
  fi
  echo "Notarizing DMG with notarytool profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG" --wait --keychain-profile "$NOTARY_PROFILE"
  echo "Stapling notarization ticket…"
  xcrun stapler staple "$DMG" >/dev/null
  echo "Notarized + stapled."
fi

echo "Done:"
echo "  $DMG"
