#!/bin/zsh
# 由 PowerLock.app 以管理员权限调用：安装或更新 root 助手与 LaunchDaemon。
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

TOOL=/Library/PrivilegedHelperTools/com.powerlock.helper
STATE="/Library/Application Support/PowerLock"

# 1.0.x 的助手没有版本号，也不记录 disablesleep 是不是自己设置的。
from_v1=0
if [[ -f "$TOOL" ]] && ! grep -q '^readonly HELPER_VERSION=' "$TOOL"; then
  from_v1=1
fi

mkdir -p /Library/PrivilegedHelperTools
# bootout 会让旧助手退出，旧助手退出前会恢复 disablesleep 0。
launchctl bootout system/com.powerlock.helper 2>/dev/null || true

# 旧助手被强制结束、没来得及恢复时，把留下的 disablesleep 1 交给新助手管理。
if (( from_v1 )); then
  sleep_disabled=$(/usr/bin/pmset -g 2>/dev/null | awk '/SleepDisabled/{print $2; exit}') || sleep_disabled=""
  if [[ "$sleep_disabled" == "1" ]]; then
    mkdir -p "$STATE"
    : > "$STATE/disablesleep-owned"
  fi
fi

/usr/bin/install -m 755 -o root -g wheel "$SRC/powerlock-helper.sh" "$TOOL"
/usr/bin/install -m 644 -o root -g wheel "$SRC/com.powerlock.helper.plist" /Library/LaunchDaemons/com.powerlock.helper.plist

launchctl bootstrap system /Library/LaunchDaemons/com.powerlock.helper.plist
launchctl enable system/com.powerlock.helper 2>/dev/null || true
launchctl kickstart -k system/com.powerlock.helper 2>/dev/null || true

echo "installed"
