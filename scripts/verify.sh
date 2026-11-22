#!/bin/zsh
# 安装后验收：检查 App、助手、launchd、pmset、屏幕保护与登录项。
# 用法：./scripts/verify.sh
set -u
cd "$(dirname "$0")/.."

PASS=0
FAIL=0

ok()   { echo "✅ $1"; PASS=$((PASS + 1)); }
bad()  { echo "❌ $1"; FAIL=$((FAIL + 1)); }
check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

CONFIG="$HOME/Library/Application Support/PowerLock/config.plist"
APP="/Applications/PowerLock.app"
HELPER_PLIST="/Library/LaunchDaemons/com.powerlock.helper.plist"
HELPER_TOOL="/Library/PrivilegedHelperTools/com.powerlock.helper"

echo "PowerLock 安装验收"
echo "------------------"

check "App 已安装: $APP" test -d "$APP"
check "App 正在运行" pgrep -f "$APP/Contents/MacOS/PowerLock"
check "助手 plist 存在" test -f "$HELPER_PLIST"
check "助手程序存在" test -f "$HELPER_TOOL"
check "助手进程运行中" pgrep -f "$HELPER_TOOL"
check "登录项存在" test -f "$HOME/Library/LaunchAgents/com.powerlock.login.plist"

if [[ -f "$HELPER_TOOL" ]]; then
  perms=$(stat -f "%Su:%Sg %Sp" "$HELPER_TOOL" 2>/dev/null)
  if [[ "$perms" == "root:wheel -rwxr-xr-x" ]]; then
    ok "助手权限 root:wheel 755"
  else
    bad "助手权限异常: $perms"
  fi
fi

if [[ -f "$CONFIG" ]]; then
  enabled=$(plutil -extract enabled raw -o - "$CONFIG" 2>/dev/null || echo false)
  no_lock=$(plutil -extract noLock raw -o - "$CONFIG" 2>/dev/null || echo false)
  lid_awake=$(plutil -extract lidAwake raw -o - "$CONFIG" 2>/dev/null || echo false)
  echo "配置: enabled=$enabled noLock=$no_lock lidAwake=$lid_awake"
else
  enabled=false
  no_lock=false
  lid_awake=false
  bad "配置文件不存在"
fi

power_line=$(pmset -g ps 2>/dev/null | head -n 1)
if [[ "$power_line" == *"AC Power"* ]]; then
  on_ac=true
  echo "电源: AC"
else
  on_ac=false
  echo "电源: Battery"
fi

sleep_disabled=$(pmset -g 2>/dev/null | awk '/SleepDisabled/ {print $2; exit}')
[[ -z "$sleep_disabled" ]] && sleep_disabled=0
if [[ "$enabled" == "true" && "$on_ac" == true && "$lid_awake" == "true" ]]; then
  [[ "$sleep_disabled" == "1" ]] && ok "AC + 合盖运行开启: SleepDisabled=1" || bad "AC 下 SleepDisabled 应为 1，实际 $sleep_disabled"
else
  [[ "$sleep_disabled" == "0" ]] && ok "非目标状态: SleepDisabled=0" || bad "SleepDisabled 应为 0，实际 $sleep_disabled"
fi

ac_display=$(pmset -g custom 2>/dev/null | awk '/^AC Power:/{f=1} f && $1=="displaysleep"{print $2; exit}')
if [[ "$enabled" == "true" && "$on_ac" == true && "$no_lock" == "true" ]]; then
  [[ "$ac_display" == "0" ]] && ok "AC 显示器不休眠" || bad "AC 显示器休眠应为 0，实际 ${ac_display:-?}"
else
  [[ "$ac_display" != "0" ]] && ok "AC 显示器休眠保持原值 ($ac_display)" || echo "ℹ️  AC 显示器休眠为 0（可能是用户原有设置）"
fi

idle=$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null || echo "")
if [[ "$enabled" == "true" && "$on_ac" == true && "$no_lock" == "true" ]]; then
  [[ "$idle" == "0" ]] && ok "屏幕保护不自动启动" || bad "屏幕保护 idleTime 应为 0，实际 ${idle:-?}"
else
  echo "ℹ️  屏幕保护 idleTime=${idle:-未知}"
fi

echo "------------------"
echo "通过 $PASS 项，失败 $FAIL 项"
[[ $FAIL -eq 0 ]] || exit 1
