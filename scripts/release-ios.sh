#!/bin/bash
# Usage:
#   bash scripts/release-ios.sh

set -euo pipefail

cd "$(dirname "$0")/.."

[[ $(git branch --show-current) == main ]] || { echo "Please release from the main branch"; exit 1; }
[[ -z $(git status --porcelain) ]]         || { echo "Working tree has uncommitted changes"; exit 1; }

git fetch origin main --tags --quiet

# App Store Connect API key (Users and Access → Integrations → Team Keys)
ASC_KEY_ID=2GF2XJF2WX
ASC_ISSUER_ID=YOUR-ISSUER-ID
ASC_AUTH=(
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
  -authenticationKeyID $ASC_KEY_ID
  -authenticationKeyIssuerID $ASC_ISSUER_ID
)

# 1. Choose version (tags look like ios-v1.2.3-202610011530)
LATEST=$(git tag -l 'ios-v*' --sort=-v:refname | head -1)
CURRENT=${LATEST#ios-v}
CURRENT=${CURRENT%-*}
CURRENT=${CURRENT:-1.0.0}
IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"

PATCH_V="$MAJOR.$MINOR.$((PATCH + 1))"
MINOR_V="$MAJOR.$((MINOR + 1)).0"
MAJOR_V="$((MAJOR + 1)).0.0"

CHOICE=$(gum choose --header "Current iOS version: $CURRENT. Choose the version to upload" \
  --selected "$CURRENT  same (new build)" \
  "$CURRENT  same (new build)" "$PATCH_V  patch" "$MINOR_V  minor" "$MAJOR_V  major" "custom")

case $CHOICE in
  custom) VERSION=$(gum input --header "Enter version" --placeholder "x.y.z") ;;
  *)      VERSION=${CHOICE%% *} ;;
esac

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must be in x.y.z format"; exit 1; }

# Timestamp build numbers stay unique even when the same commit is uploaded twice
BUILD_NUMBER=$(date +%Y%m%d%H%M)
TAG="ios-v$VERSION-$BUILD_NUMBER"
BUILD=build/ios

gum confirm "Upload Rede iOS $VERSION ($BUILD_NUMBER) to TestFlight?" || exit 0

# 2. Archive (= Xcode → Product → Archive)
rm -rf $BUILD
gum spin --title "Building $VERSION ($BUILD_NUMBER)…" --show-error -- \
  xcodebuild archive -quiet -allowProvisioningUpdates "${ASC_AUTH[@]}" \
    -scheme "Rede iOS" -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath $BUILD/Rede.xcarchive \
    -derivedDataPath build/DerivedData \
    MARKETING_VERSION=$VERSION \
    CURRENT_PROJECT_VERSION=$BUILD_NUMBER

# 3. Export and upload (= Organizer → Distribute App → TestFlight Internal Only)
gum spin --title "Uploading to App Store Connect…" --show-error -- \
  xcodebuild -exportArchive -quiet -allowProvisioningUpdates "${ASC_AUTH[@]}" \
    -archivePath $BUILD/Rede.xcarchive \
    -exportOptionsPlist scripts/ExportOptions-iOS.plist \
    -exportPath $BUILD/export

# 4. Tag the uploaded commit
git push origin main
git tag "$TAG"
git push origin "$TAG" --quiet

echo "Uploaded $TAG — it will appear in TestFlight after processing"
