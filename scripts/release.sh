#!/bin/bash
# Usage:
#   bash scripts/release.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# 0. 前置检查
[[ $(git branch --show-current) == main ]] || { echo "请在 main 分支发布"; exit 1; }
[[ -z $(git status --porcelain) ]]         || { echo "工作区有未提交的改动"; exit 1; }

# 1. 选择版本号
LATEST=$(git tag -l 'v*' --sort=-v:refname | head -1)
CURRENT=${LATEST#v}
CURRENT=${CURRENT:-0.0.0}
IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"

PATCH_V="$MAJOR.$MINOR.$((PATCH + 1))"
MINOR_V="$MAJOR.$((MINOR + 1)).0"
MAJOR_V="$((MAJOR + 1)).0.0"

echo "当前版本：$CURRENT"
echo "  1) $PATCH_V  修订版本（默认）"
echo "  2) $MINOR_V  次版本"
echo "  3) $MAJOR_V  主版本"
echo "  4) 自定义"
read -rp "请选择 [1]: " CHOICE

case ${CHOICE:-1} in
  1) VERSION=$PATCH_V ;;
  2) VERSION=$MINOR_V ;;
  3) VERSION=$MAJOR_V ;;
  4) read -rp "输入版本号: " VERSION ;;
  *) echo "无效选择"; exit 1 ;;
esac

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "版本号格式应为 x.y.z"; exit 1; }
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "v$VERSION 已存在"; exit 1
fi

TAG="v$VERSION"

# 1. Archive（= Xcode → Product → Archive）
rm -rf $BUILD/MyReader.xcarchive $BUILD/dmg
xcodebuild archive -quiet \
  -scheme MyReader -configuration Release \
  -archivePath $BUILD/MyReader.xcarchive \
  -derivedDataPath $BUILD/DerivedData \
  MARKETING_VERSION=$VERSION \
  CURRENT_PROJECT_VERSION=$BUILD_NUMBER

# 2. 制作 dmg（= Copy App + 手动 hdiutil）
mkdir -p $BUILD/dmg dist
cp -R $BUILD/MyReader.xcarchive/Products/Applications/MyReader.app $BUILD/dmg/
ln -s /Applications $BUILD/dmg/Applications
hdiutil create -volname MyReader -srcfolder $BUILD/dmg -ov -format UDZO "$DMG"

# 3. 发布到 GitHub
# git tag "$TAG"
# git push origin main "$TAG"
# gh release create "$TAG" "$DMG" \
#   --title "MyReader $VERSION" \
#   --notes-file scripts/release-notes.md \
#   --generate-notes

# echo "已发布 $TAG"