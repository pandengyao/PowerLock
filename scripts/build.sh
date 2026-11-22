#!/bin/zsh
# 构建 PowerLock.app
#   VERSION=1.0.0 BUILD=1 ./scripts/build.sh
#   UNIVERSAL=1 ./scripts/build.sh   # 生成 arm64 + x86_64
set -euo pipefail
cd "$(dirname "$0")/.."

# 版本号默认取 Resources/Info.plist，保证本地构建和 Release 一致。
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
BUILD="${BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)}"
APP="build/PowerLock.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Helper"

SOURCES=(Sources/*.swift)

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 "${SOURCES[@]}" -o build/PowerLock-arm64
  swiftc -O -swift-version 5 -target x86_64-apple-macosx13.0 "${SOURCES[@]}" -o build/PowerLock-x86_64
  lipo -create build/PowerLock-arm64 build/PowerLock-x86_64 -output "$APP/Contents/MacOS/PowerLock"
  rm -f build/PowerLock-arm64 build/PowerLock-x86_64
else
  swiftc -O -swift-version 5 "${SOURCES[@]}" -o "$APP/Contents/MacOS/PowerLock"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Helper/powerlock-helper.sh "$APP/Contents/Resources/Helper/"
cp Resources/Helper/com.powerlock.helper.plist "$APP/Contents/Resources/Helper/"
cp Resources/Helper/install-helper.sh "$APP/Contents/Resources/Helper/"
cp Resources/Helper/uninstall-helper.sh "$APP/Contents/Resources/Helper/"
chmod 755 "$APP/Contents/Resources/Helper/"*.sh
chmod 755 "$APP/Contents/MacOS/PowerLock"

codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP"
echo "Built $APP"
