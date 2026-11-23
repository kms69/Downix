#!/bin/bash
# Build a release of Downix and (optionally) publish it to the public releases repo.
#   ./release.sh 1.0.0            build dist/Downix-1.0.0.zip and .dmg
#   ./release.sh 1.0.0 --publish  also create the GitHub release (needs the gh CLI, logged in)
set -e
cd "$(dirname "$0")"

RELEASE_REPO="kms69/Downex"       # public repo that holds only the downloads
VERSION="${1:?usage: ./release.sh <version, e.g. 1.0.0> [--publish]}"
VERSION="${VERSION#v}"

echo "🔨 Building release $VERSION ..."
CONFIG=release ./bundle_app.sh

BUILT="$(ls -d ./*.app | head -n 1)"
[ -d "$BUILT" ] || { echo "❌ no .app found"; exit 1; }

rm -rf dist && mkdir -p dist/stage
APP="dist/stage/Downix.app"
cp -R "$BUILT" "$APP"

# browser extensions ship inside the app (the app copies them to ~/Downix Extensions)
mkdir -p "$APP/Contents/Resources/BrowserExtensions"
for b in Brave Chrome Edge Firefox; do
  [ -d "BrowserExtensions/$b" ] && cp -R "BrowserExtensions/$b" "$APP/Contents/Resources/BrowserExtensions/$b"
done

# version shown in About / used by Check for Updates
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

# smaller, harder to read: drop local symbols, then sign (ad-hoc: needed to run on Apple Silicon)
for exe in "$APP"/Contents/MacOS/*; do strip -x "$exe" 2>/dev/null || true; done
codesign --force --deep --sign - "$APP"

ditto -c -k --keepParent "$APP" "dist/Downix-$VERSION.zip"
hdiutil create -volname "Downix" -srcfolder "$APP" -ov -format UDZO "dist/Downix-$VERSION.dmg" >/dev/null
rm -rf dist/stage
( cd dist && shasum -a 256 Downix-* )
echo "✅ dist/Downix-$VERSION.zip and dist/Downix-$VERSION.dmg are ready"

if [ "$2" = "--publish" ]; then
  command -v gh >/dev/null || { echo "❌ install the GitHub CLI first: brew install gh && gh auth login"; exit 1; }
  gh release create "v$VERSION" "dist/Downix-$VERSION.dmg" "dist/Downix-$VERSION.zip" \
     --repo "$RELEASE_REPO" --title "Downix $VERSION" --notes "Downix Download Manager $VERSION. Open the .dmg and drag Downix to Applications. First launch: see the README."
  echo "🚀 published: https://github.com/$RELEASE_REPO/releases/tag/v$VERSION"
fi
