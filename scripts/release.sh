#!/bin/bash
# Usage:
#   bash scripts/release.sh

set -euo pipefail

cd "$(dirname "$0")/.."

[[ $(git branch --show-current) == main ]] || { echo "Please release from the main branch"; exit 1; }
[[ -z $(git status --porcelain) ]]         || { echo "Working tree has uncommitted changes"; exit 1; }

git fetch origin main --tags --quiet

# 1. Choose version
LATEST=$(git tag -l 'v*' --sort=-v:refname | head -1)
CURRENT=${LATEST#v}
CURRENT=${CURRENT:-0.0.0}
IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"

PATCH_V="$MAJOR.$MINOR.$((PATCH + 1))"
MINOR_V="$MAJOR.$((MINOR + 1)).0"
MAJOR_V="$((MAJOR + 1)).0.0"

CHOICE=$(gum choose --header "Current version: $CURRENT. Choose the version to release" \
  --selected "$PATCH_V  patch" \
  "$PATCH_V  patch" "$MINOR_V  minor" "$MAJOR_V  major" "custom")

case $CHOICE in
  custom) VERSION=$(gum input --header "Enter version" --placeholder "x.y.z") ;;
  *)      VERSION=${CHOICE%% *} ;;
esac

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must be in x.y.z format"; exit 1; }
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "v$VERSION already exists"; exit 1
fi

TAG="v$VERSION"
BUILD_NUMBER=$(git rev-list --count HEAD)
BUILD=build
DMG=dist/MyReader-$VERSION.dmg

gum confirm "Build and release $TAG (build $BUILD_NUMBER)?" || exit 0

# 2. Archive (= Xcode → Product → Archive)
rm -rf $BUILD/MyReader.xcarchive $BUILD/dmg
gum spin --title "Building ${TAG}…" --show-error -- \
  xcodebuild archive -quiet \
    -scheme MyReader -configuration Release \
    -archivePath $BUILD/MyReader.xcarchive \
    -derivedDataPath $BUILD/DerivedData \
    MARKETING_VERSION=$VERSION \
    CURRENT_PROJECT_VERSION=$BUILD_NUMBER

# 3. Create dmg (= Copy App + manual hdiutil)
mkdir -p $BUILD/dmg dist
cp -R $BUILD/MyReader.xcarchive/Products/Applications/MyReader.app $BUILD/dmg/
ln -s /Applications $BUILD/dmg/Applications
gum spin --title "Creating dmg…" --show-error -- \
  hdiutil create -volname MyReader -srcfolder $BUILD/dmg -ov -format UDZO "$DMG"

# 4. Generate appcast (signs the dmg with the EdDSA key in Keychain)
rm -rf $BUILD/appcast && mkdir -p $BUILD/appcast
cp "$DMG" $BUILD/appcast/
$BUILD/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast $BUILD/appcast \
  --download-url-prefix "https://github.com/qyangcv/MyReader/releases/download/$TAG/"

# 5. Publish to GitHub (GitHub creates the tag together with the release)
CHANGES=$(git log ${LATEST:+$LATEST..}HEAD --no-merges --pretty='- %s')
NOTES=$(printf '## 更新内容\n\n%s\n\n%s' "$CHANGES" "$(< scripts/release-notes.md)")

git push origin main
gh release create "$TAG" "$DMG" $BUILD/appcast/appcast.xml \
  --target "$(git rev-parse HEAD)" \
  --title "MyReader $VERSION" \
  --notes "$NOTES" \
  --generate-notes
git fetch --tags --quiet

echo "Released $TAG"
