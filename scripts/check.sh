#!/bin/zsh
# 本地/CI 冒烟检查：脚本语法、plist、构建、CLI 状态。
set -euo pipefail
cd "$(dirname "$0")/.."

zsh -n Resources/Helper/powerlock-helper.sh
zsh -n Resources/Helper/install-helper.sh
zsh -n Resources/Helper/uninstall-helper.sh

plutil -lint Resources/Info.plist
plutil -lint Resources/Helper/com.powerlock.helper.plist

VERSION="${VERSION:-0.0.0}" BUILD="${BUILD:-0}" ./scripts/build.sh
./build/PowerLock.app/Contents/MacOS/PowerLock --status | sed -n '1,8p'

echo "OK"
