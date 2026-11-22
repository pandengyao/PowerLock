#!/bin/zsh
# 由 PowerLock.app 以管理员权限调用：卸载 root 助手并恢复系统睡眠设置。
set -u

TOOL=/Library/PrivilegedHelperTools/com.powerlock.helper
STATE="/Library/Application Support/PowerLock"

# 1.0.x 的助手不记录 disablesleep 是不是自己设置的；装的是旧助手时，按 PowerLock 设置的处理。
owned=0
[[ -f "$STATE/disablesleep-owned" ]] && owned=1
if [[ -f "$TOOL" ]] && ! grep -q '^readonly HELPER_VERSION=' "$TOOL"; then
  owned=1
fi

# bootout 会给助手发 TERM，助手退出前自己恢复设置；下面是助手没能正常退出时的兜底。
launchctl bootout system/com.powerlock.helper 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.powerlock.helper.plist
rm -f "$TOOL"

if (( owned )); then
  /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 || true
fi

if [[ -f "$STATE/ac-display-sleep" ]]; then
  value=$(cat "$STATE/ac-display-sleep" 2>/dev/null)
  [[ "$value" == <-> ]] || value=10
  /usr/bin/pmset -c displaysleep "$value" >/dev/null 2>&1 || true
fi
rm -rf "$STATE"

echo "uninstalled"
