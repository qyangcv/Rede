#!/bin/bash
# Usage:
#   bash scripts/release-ios.sh

set -euo pipefail

cd "$(dirname "$0")/.."

[[ $(git branch --show-current) == main ]] || { echo "Please release from the main branch"; exit 1; }
[[ -z $(git status --porcelain) ]]         || { echo "Working tree has uncommitted changes"; exit 1; }

git fetch origin main --tags --quiet

# App Store Connect API key (Users and Access → Integrations → Team Keys)
ASC_KEY_ID=3T9BZJ4X96
ASC_ISSUER_ID=a1359993-1cf9-4beb-aacc-9b0dee256ca2
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
ASC_AUTH=(
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID $ASC_KEY_ID
  -authenticationKeyIssuerID $ASC_ISSUER_ID
)

APP_ID=6817790500
BETA_GROUP_ID=ea9d9708-80a6-4832-8594-2b7118f9f135

asc() {
  curl -sSg --fail-with-body -X "$1" "https://api.appstoreconnect.apple.com/v1/$2" \
    -H "Authorization: Bearer $(swift scripts/asc-jwt.swift $ASC_KEY_ID $ASC_ISSUER_ID "$ASC_KEY_PATH")" \
    -H "Content-Type: application/json" \
    ${3:+-d} ${3:+"$3"}
}

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

# 1b. Generate the CloudKit schema from the models, commit it if changed, and deploy it to Production
bash scripts/cloudkit-schema.sh release

# 1c. What to Test for TestFlight testers
NOTES_FILE=$(mktemp -t rede-what-to-test)
zsh -f scripts/what-to-test.zsh "$NOTES_FILE" "$(git log --format='- %s' --grep='^iOS' "${LATEST:+$LATEST..}HEAD")"
NOTES=$(<"$NOTES_FILE")
rm "$NOTES_FILE"
[[ -n $NOTES ]] || { echo "What to Test cannot be empty"; exit 1; }

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

# 3. Export and upload (= Organizer → Distribute App → TestFlight)
gum spin --title "Uploading to App Store Connect…" --show-error -- \
  xcodebuild -exportArchive -quiet -allowProvisioningUpdates "${ASC_AUTH[@]}" \
    -archivePath $BUILD/Rede.xcarchive \
    -exportOptionsPlist scripts/ExportOptions-iOS.plist \
    -exportPath $BUILD/export

# 4. Push main and tag the uploaded commit
git tag "$TAG"
git push --quiet origin main "$TAG"
echo "Pushed branch main -> origin/main"
echo "Pushed tag $TAG -> origin/$TAG"

# 5. Wait for processing, then hand the build to external testers
echo "Waiting for App Store Connect to process ${BUILD_NUMBER}…"
while :; do
  BUILD_JSON=$(asc GET "builds?filter[app]=$APP_ID&filter[version]=$BUILD_NUMBER")
  STATE=$(jq -r '.data[0].attributes.processingState // empty' <<< "$BUILD_JSON")
  case $STATE in
    VALID)          break ;;
    FAILED|INVALID) echo "Build processing $STATE"; exit 1 ;;
  esac
  sleep 30
done
BUILD_ID=$(jq -r '.data[0].id' <<< "$BUILD_JSON")

LOCALIZATION_ID=$(asc GET "betaBuildLocalizations?filter[build]=$BUILD_ID&filter[locale]=zh-Hans" | jq -r '.data[0].id')
asc PATCH "betaBuildLocalizations/$LOCALIZATION_ID" "$(jq -n --arg id "$LOCALIZATION_ID" --arg notes "$NOTES" \
  '{data: {type: "betaBuildLocalizations", id: $id, attributes: {whatsNew: $notes}}}')" > /dev/null

asc POST "builds/$BUILD_ID/relationships/betaGroups" \
  "{\"data\":[{\"type\":\"betaGroups\",\"id\":\"$BETA_GROUP_ID\"}]}" > /dev/null

asc POST betaAppReviewSubmissions \
  "{\"data\":{\"type\":\"betaAppReviewSubmissions\",\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}}}}" > /dev/null

echo "Submitted $TAG for Beta App Review — testers get it automatically once approved"
