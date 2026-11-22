#!/bin/zsh
# 由 PowerLock.app 以管理员权限调用：卸载 root 助手并恢复系统睡眠设置。
set -u

launchctl bootout system/com.powerlock.helper 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.powerlock.helper.plist
rm -f /Library/PrivilegedHelperTools/com.powerlock.helper

/usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 || true

SAVED="/Library/Application Support/PowerLock/ac-display-sleep"
if [[ -f "$SAVED" ]]; then
  value=$(cat "$SAVED" 2>/dev/null)
  [[ "$value" == <-> ]] || value=10
  /usr/bin/pmset -c displaysleep "$value" >/dev/null 2>&1 || true
fi
rm -rf "/Library/Application Support/PowerLock"

echo "uninstalled"
