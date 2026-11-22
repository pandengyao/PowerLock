#!/bin/zsh
# 打包 GitHub Release 产物：zip + dmg + SHA256
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
export VERSION
export UNIVERSAL="${UNIVERSAL:-1}"

./scripts/build.sh

DIST="build/dist"
mkdir -p "$DIST"
rm -f "$DIST/PowerLock-$VERSION.zip" "$DIST/PowerLock-$VERSION.dmg" "$DIST/SHA256SUMS.txt"

ditto -c -k --keepParent build/PowerLock.app "$DIST/PowerLock-$VERSION.zip"
hdiutil create -volname "PowerLock $VERSION" -srcfolder build/PowerLock.app -ov -format UDZO "$DIST/PowerLock-$VERSION.dmg" >/dev/null
shasum -a 256 "$DIST"/*.zip "$DIST"/*.dmg > "$DIST/SHA256SUMS.txt"

echo "Packaged:"
ls -lh "$DIST"
