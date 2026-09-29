#!/bin/bash
# 새 버전 배포: 빌드 → zip → 태그 → GitHub 릴리스 → Homebrew 탭 갱신
#   ./scripts/release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

VERSION="${1:?버전을 주세요 (예: ./scripts/release.sh 0.1.0)}"
TAG="v${VERSION}"
ZIP="build/${APP_NAME}.zip"

[ -z "$(git status --porcelain)" ] || { echo "커밋하지 않은 변경이 있어요"; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "$TAG 태그가 이미 있어요"; exit 1; }

VERSION="$VERSION" ./scripts/build-app.sh
rm -f "$ZIP"
ditto -c -k --keepParent "build/${APP_NAME}.app" "$ZIP"
SHA256=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "▸ $ZIP  sha256=$SHA256"

git tag "$TAG"
git push origin main "$TAG"
gh release create "$TAG" "$ZIP" --title "${APP_NAME} ${TAG}" --generate-notes

echo "▸ Homebrew 탭 갱신 ($TAP_REPO)"
TAP=$(mktemp -d)
gh repo clone "$TAP_REPO" "$TAP" -- -q
# 새로 받은 복사본에도 이 저장소와 같은 커밋 신원을 쓴다 (전역 설정의 다른 이메일이 섞이지 않게)
git -C "$TAP" config user.name "$(git config user.name)"
git -C "$TAP" config user.email "$(git config user.email)"
mkdir -p "$TAP/Casks"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__SHA256__/${SHA256}/" \
    -e "s/__OWNER__/${OWNER}/g" -e "s/__BUNDLE_ID__/${BUNDLE_ID}/g" \
    scripts/session-board.rb.template > "$TAP/Casks/session-board.rb"
git -C "$TAP" add Casks/session-board.rb
git -C "$TAP" commit -q -m "session-board ${VERSION}"
git -C "$TAP" push -q
rm -rf "$TAP"
echo "✓ ${TAG} 배포 완료 — brew install --cask ${OWNER}/tap/session-board"
