#!/bin/sh
set -e

# ══════════════════════════════════════════
#  参数
# ══════════════════════════════════════════
APP_NAME="${1:?缺少 APP_NAME}"
BUNDLE_ID="${2:?缺少 BUNDLE_ID}"
IPA_PATH="${3:?缺少 IPA_PATH}"
BUILDS_REPO="${4:?缺少 BUILDS_REPO}"   # 格式: username/firefly-chat-builds

GITHUB_TOKEN="${GITHUB_TOKEN:?请在 Xcode Cloud 设置环境变量 GITHUB_TOKEN}"

VERSION="${CI_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
COMMIT_MSG="${CI_COMMIT_MESSAGE:-build $VERSION}"
GITHUB_USER=$(echo "$BUILDS_REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$BUILDS_REPO" | cut -d/ -f2)
PAGES_URL="https://${GITHUB_USER}.github.io/${REPO_NAME}"
TAG="build-${VERSION}"
IPA_FILENAME="${APP_NAME}.ipa"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  $APP_NAME  |  build $VERSION"
echo "  仓库: $BUILDS_REPO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ══════════════════════════════════════════
#  1. 安装依赖
# ══════════════════════════════════════════
if ! command -v gh &> /dev/null; then
  echo "▶ 安装 gh CLI..."
  brew install gh --quiet
fi

echo "$GITHUB_TOKEN" | gh auth login --with-token

# ══════════════════════════════════════════
#  2. 自动创建 builds 仓库（首次使用时）
# ══════════════════════════════════════════
if ! gh repo view "$BUILDS_REPO" &> /dev/null; then
  echo "▶ 首次使用，自动创建仓库 $BUILDS_REPO ..."

  gh repo create "$BUILDS_REPO" \
    --public \
    --description "$APP_NAME iOS builds" \
    --add-readme

  # 创建 gh-pages 分支（Pages 需要至少一次 commit）
  INIT_DIR=$(mktemp -d)
  git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${BUILDS_REPO}.git" "$INIT_DIR"
  cd "$INIT_DIR"
  git checkout --orphan gh-pages
  git rm -rf . 2>/dev/null || true
  echo "# $APP_NAME Builds" > index.html
  git add index.html
  git config user.email "ci-bot@ios-distribute"
  git config user.name "iOS Distribute Bot"
  git commit -m "init gh-pages"
  git push origin gh-pages
  cd /

  # 开启 GitHub Pages
  gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    "/repos/${BUILDS_REPO}/pages" \
    -f source='{"branch":"gh-pages","path":"/"}' \
    2>/dev/null || true  # 已开启时忽略报错

  echo "✅ 仓库创建完成，Pages URL: $PAGES_URL"
  echo "⏳ 等待 Pages 初始化..."
  sleep 10
fi

# ══════════════════════════════════════════
#  3. 上传 IPA 到 GitHub Releases
# ══════════════════════════════════════════
echo "▶ 上传 IPA..."
cp "$IPA_PATH" "/tmp/$IPA_FILENAME"

gh release create "$TAG" "/tmp/$IPA_FILENAME" \
  --repo "$BUILDS_REPO" \
  --title "$APP_NAME build $VERSION" \
  --notes "$COMMIT_MSG"

IPA_URL="https://github.com/${BUILDS_REPO}/releases/download/${TAG}/${IPA_FILENAME}"
echo "  IPA URL: $IPA_URL"

# ══════════════════════════════════════════
#  4. 生成 manifest.plist
# ══════════════════════════════════════════
echo "▶ 生成 manifest.plist..."
PLIST_URL="${PAGES_URL}/manifest.plist"

sed \
  -e "s|{{IPA_URL}}|$IPA_URL|g" \
  -e "s|{{BUNDLE_ID}}|$BUNDLE_ID|g" \
  -e "s|{{VERSION}}|$VERSION|g" \
  -e "s|{{APP_NAME}}|$APP_NAME|g" \
  "$SCRIPT_DIR/../template/manifest.plist" > /tmp/manifest.plist

# ══════════════════════════════════════════
#  5. 生成安装页 index.html
# ══════════════════════════════════════════
echo "▶ 生成安装页..."
INSTALL_URL="itms-services://?action=download-manifest&url=${PLIST_URL}"
BUILD_DATE=$(date "+%Y-%m-%d %H:%M")

sed \
  -e "s|{{APP_NAME}}|$APP_NAME|g" \
  -e "s|{{VERSION}}|$VERSION|g" \
  -e "s|{{COMMIT_MSG}}|$COMMIT_MSG|g" \
  -e "s|{{INSTALL_URL}}|$INSTALL_URL|g" \
  -e "s|{{IPA_URL}}|$IPA_URL|g" \
  -e "s|{{BUILD_DATE}}|$BUILD_DATE|g" \
  -e "s|{{PAGES_URL}}|$PAGES_URL|g" \
  "$SCRIPT_DIR/../template/index.html" > /tmp/index.html

# ══════════════════════════════════════════
#  6. 推送到 gh-pages
# ══════════════════════════════════════════
echo "▶ 更新安装页..."
WORK_DIR=$(mktemp -d)
git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${BUILDS_REPO}.git" "$WORK_DIR"
cd "$WORK_DIR"
git checkout gh-pages

cp /tmp/manifest.plist .
cp /tmp/index.html .

git config user.email "ci-bot@ios-distribute"
git config user.name "iOS Distribute Bot"
git add manifest.plist index.html
git commit -m "build $VERSION: $COMMIT_MSG"
git push origin gh-pages

# ══════════════════════════════════════════
#  完成
# ══════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 发布完成！"
echo "  安装页: $PAGES_URL"
echo "  测试员用 iPhone 打开上方链接即可安装"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"