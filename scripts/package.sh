#!/usr/bin/env bash
# Build a Release .app and zip it for GitHub Releases / manual distribution.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

VERSION="$(
  python3 - <<'PY'
import re, pathlib
text = pathlib.Path("project.yml").read_text()
m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
print(m.group(1) if m else "0.0.0")
PY
)"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building NotchBoard ($CONFIGURATION) v$VERSION"
rm -rf "$DERIVED_DATA"
xcodebuild \
  -project NotchBoard.xcodeproj \
  -scheme NotchBoard \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build

APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/NotchBoard.app"
if [[ ! -d "$APP" ]]; then
  echo "error: expected app at $APP" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
ZIP_NAME="NotchBoard-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "==> Packaging $ZIP_NAME"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_PATH"

# Convenience copy for GitHub Actions / local testing
cp -f "$ZIP_PATH" "$DIST_DIR/NotchBoard-latest.zip"

echo
echo "Packed: $ZIP_PATH"
echo "Install: unzip and move NotchBoard.app to /Applications"
echo "Gatekeeper tip (unsigned download): xattr -cr /Applications/NotchBoard.app"
