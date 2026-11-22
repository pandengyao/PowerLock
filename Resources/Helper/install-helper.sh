#!/bin/zsh
# 由 PowerLock.app 以管理员权限调用：安装 root 助手与 LaunchDaemon。
set -euo pipefail

BUNDLE="${1:-}"
if [[ -z "$BUNDLE" ]]; then
  echo "usage: install-helper.sh /Applications/PowerLock.app" >&2
  exit 2
fi

SRC="$BUNDLE/Contents/Resources/Helper"
if [[ ! -f "$SRC/powerlock-helper.sh" || ! -f "$SRC/com.powerlock.helper.plist" ]]; then
  echo "helper resources missing in $SRC" >&2
  exit 1
fi

mkdir -p /Library/PrivilegedHelperTools
launchctl bootout system/com.powerlock.helper 2>/dev/null || true

/usr/bin/install -m 755 -o root -g wheel "$SRC/powerlock-helper.sh" /Library/PrivilegedHelperTools/com.powerlock.helper
/usr/bin/install -m 644 -o root -g wheel "$SRC/com.powerlock.helper.plist" /Library/LaunchDaemons/com.powerlock.helper.plist

launchctl bootstrap system /Library/LaunchDaemons/com.powerlock.helper.plist
launchctl enable system/com.powerlock.helper 2>/dev/null || true
launchctl kickstart -k system/com.powerlock.helper 2>/dev/null || true

echo "installed"
