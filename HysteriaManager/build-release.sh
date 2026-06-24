#!/usr/bin/env bash
#
# Builds a Release HysteriaManager.app and installs it to /Applications.
# Run on macOS:  ./build-release.sh
#
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

derived="$here/.build"
app_name="HysteriaManager.app"
dest="/Applications/$app_name"

echo "==> Building Release (this may take a minute)…"
xcodebuild \
  -project HysteriaManager.xcodeproj \
  -scheme HysteriaManager \
  -configuration Release \
  -derivedDataPath "$derived" \
  -destination "platform=macOS" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  clean build

app="$derived/Build/Products/Release/$app_name"
[[ -d "$app" ]] || { echo "ERROR: build produced no app at $app" >&2; exit 1; }

echo "==> Installing to $dest"
if [[ -w /Applications ]]; then
  rm -rf "$dest"
  cp -R "$app" "$dest"
else
  echo "    /Applications needs admin — using sudo"
  sudo rm -rf "$dest"
  sudo cp -R "$app" "$dest"
fi

# Clear the quarantine flag so it launches without a Gatekeeper prompt.
xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

echo ""
echo "✅ Installed: $dest"
echo "   Launch it from Applications (or: open \"$dest\")."
