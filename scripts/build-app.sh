#!/bin/bash
# SessionBoard.app 을 만든다 (Apple Silicon·Intel 공용, 자체 서명)
#   ./scripts/build-app.sh            → build/SessionBoard.app
#   ./scripts/build-app.sh --install  → /Applications 에도 복사
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
APP="build/${APP_NAME}.app"

echo "▸ 빌드 (v${VERSION})"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${APP_NAME}"

echo "▸ 앱 묶기"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp -R Resources/scripts "$APP/Contents/Resources/scripts"
chmod 755 "$APP/Contents/Resources/scripts/"*.sh
sed -e "s/__BUNDLE_ID__/${BUNDLE_ID}/" -e "s/__VERSION__/${VERSION}/g" -e "s|__REPO__|${OWNER}/session-board|" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/" || true

echo "▸ 자체 서명"
codesign --force --deep --sign - "$APP"

if [ "${1:-}" = "--install" ]; then
  echo "▸ /Applications 에 설치"
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$APP" /Applications/
  open "/Applications/${APP_NAME}.app"
fi
echo "✓ $APP"
