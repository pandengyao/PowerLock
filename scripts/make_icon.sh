#!/bin/zsh
# 重新生成 App 图标：Resources/AppIcon.icns 和 README 用的 docs/images/icon.png。
# 只依赖 Xcode Command Line Tools（swiftc、iconutil）。改了 scripts/make_icon.swift 后运行一次并提交结果。
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O scripts/make_icon.swift -o "$TMP/make_icon"
"$TMP/make_icon" "$TMP/out" amber
iconutil -c icns "$TMP/out/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$TMP/out/icon-1024.png" docs/images/icon.png
echo "Updated Resources/AppIcon.icns and docs/images/icon.png"
