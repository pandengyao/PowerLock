#!/bin/zsh
# PowerLock 后台助手（以 root 运行）
#
# 由 launchd 启动，每 5 秒检查一次电源状态，只执行固定的 pmset 命令：
#   - 插电 + 开启「插电不锁屏」+ App 在运行：AC 显示器不休眠（displaysleep 0）
#   - 插电 + 开启「合盖后保持运行」：disablesleep 1
#   - 电池 / 关闭功能：恢复 disablesleep 0 与原来的 AC 显示器休眠时间；
#     如果是拔电、而且盖子已经合上，按系统规则立即睡眠（pmset sleepnow）
#
# 配置由 PowerLock.app 写入（仅布尔值），本脚本不会执行用户传入的命令。

set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

# 助手逻辑有变化时加 1。App 会比较内置版本和已安装版本，提示用户更新助手。
readonly HELPER_VERSION=2
readonly LABEL="com.powerlock.helper"
STATE_DIR="${POWERLOCK_STATE_DIR:-/Library/Application Support/PowerLock}"
PMSET="${POWERLOCK_PMSET:-/usr/bin/pmset}"
IOREG="${POWERLOCK_IOREG:-/usr/sbin/ioreg}"
CONFIG_OVERRIDE="${POWERLOCK_CONFIG:-}"
ONCE="${POWERLOCK_ONCE:-0}"
INTERVAL="${POWERLOCK_INTERVAL:-5}"

# disablesleep 是 PowerLock 设置的才由 PowerLock 撤销，不影响别的工具或手动设置。
OWNED_FLAG="$STATE_DIR/disablesleep-owned"

log() {
  logger -t "$LABEL" -- "$*" 2>/dev/null
}

console_user() {
  stat -f %Su /dev/console 2>/dev/null
}

user_home() {
  local user="$1"
  [[ -z "$user" || "$user" == "root" || "$user" == "loginwindow" ]] && return 1
  dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
}

# 没有登录用户（登录界面、注销或关机过程中）时返回失败。
config_path() {
  if [[ -n "$CONFIG_OVERRIDE" ]]; then
    print -r -- "$CONFIG_OVERRIDE"
    return 0
  fi
  local user home
  user=$(console_user) || return 1
  home=$(user_home "$user") || return 1
  [[ -n "$home" ]] || return 1
  print -r -- "$home/Library/Application Support/PowerLock/config.plist"
}

read_bool() {
  local file="$1" key="$2" fallback="$3" value
  value=$(plutil -extract "$key" raw -o - "$file" 2>/dev/null) || value=""
  if [[ "$value" == "true" || "$value" == "1" ]]; then
    print -r -- "true"
  elif [[ "$value" == "false" || "$value" == "0" ]]; then
    print -r -- "false"
  else
    print -r -- "$fallback"
  fi
}

# 输出 AC 或 Battery（UPS 也算 Battery）；pmset 失败或输出无法识别时返回失败。
power_source() {
  local out
  out=$("$PMSET" -g ps 2>/dev/null) || return 1
  case "${out%%$'\n'*}" in
    *"'AC Power'"*) print -r -- AC ;;
    *"'Battery Power'"*|*"'UPS Power'"*) print -r -- Battery ;;
    *) return 1 ;;
  esac
}

current_ac_display_sleep() {
  local value
  value=$("$PMSET" -g custom 2>/dev/null | awk '/^AC Power:/{found=1} found && $1=="displaysleep"{print $2; exit}')
  [[ "$value" == <-> ]] || value=10
  print -r -- "$value"
}

set_ac_display_sleep() {
  "$PMSET" -c displaysleep "$1" >/dev/null 2>&1 || true
}

# 输出 0 或 1；pmset 失败时返回失败，调用方这一轮不要据此改任何东西。
disablesleep_state() {
  local out
  out=$("$PMSET" -g 2>/dev/null) || return 1
  if [[ "$(print -r -- "$out" | awk '/SleepDisabled/{print $2; exit}')" == "1" ]]; then
    print -r -- "1"
  else
    print -r -- "0"
  fi
}

# 设置后重新读一次，确认生效才算成功。
set_disablesleep() {
  local current
  current=$(disablesleep_state) || return 1
  [[ "$current" == "$1" ]] && return 0
  "$PMSET" -a disablesleep "$1" >/dev/null 2>&1 || return 1
  current=$(disablesleep_state) || return 1
  [[ "$current" == "$1" ]] || return 1
  log "disablesleep -> $1"
}

acquire_disablesleep() {
  local current
  if [[ ! -f "$OWNED_FLAG" ]]; then
    current=$(disablesleep_state) || return 0
    # 已经是 1：是你手动或别的工具设置的，不接管，以后也不撤销。
    [[ "$current" == "1" ]] && return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    # 记不下来就不改，免得改了以后没法恢复。
    : > "$OWNED_FLAG" 2>/dev/null || return 0
  fi
  set_disablesleep 1 || true
}

# 只撤销 PowerLock 自己设置的 disablesleep。确认改回 0 以后才删除标记，
# 失败时保留标记，下一轮再试。
# 返回 0 表示这次确实把 disablesleep 从 1 改回了 0。
release_disablesleep() {
  [[ -f "$OWNED_FLAG" ]] || return 1
  local was
  was=$(disablesleep_state) || return 1
  set_disablesleep 0 || return 1
  rm -f "$OWNED_FLAG"
  [[ "$was" == "1" ]]
}

# 内核只在开合盖、插拔电源、外接显示器变化时检查盖子。
# 拔电那一刻 disablesleep 还是 1，系统不会睡；之后助手把它改回 0，
# 系统也不会再检查一次，合着盖的 Mac 就会在电池上一直醒着。
# 所以拔电后撤销 disablesleep 时，如果盖子合着、而且系统此刻本该因合盖而睡眠
# （AppleClamshellCausesSleep，外接显示器时为 No），就补一次睡眠。
sleep_if_lid_closed() {
  local lid
  lid=$("$IOREG" -r -k AppleClamshellState -d 1 2>/dev/null) || return 0
  [[ "$lid" == *'"AppleClamshellState" = Yes'* ]] || return 0
  [[ "$lid" == *'"AppleClamshellCausesSleep" = Yes'* ]] || return 0
  log "lid closed after switching to battery, sleeping now"
  "$PMSET" sleepnow >/dev/null 2>&1 || true
}

ensure_display_sleep_off() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  if [[ ! -f "$STATE_DIR/ac-display-sleep" ]]; then
    print -r -- "$(current_ac_display_sleep)" > "$STATE_DIR/ac-display-sleep" 2>/dev/null || return 0
    chmod 644 "$STATE_DIR/ac-display-sleep" 2>/dev/null || true
  fi
  if [[ "$(current_ac_display_sleep)" != "0" ]]; then
    set_ac_display_sleep 0
    log "AC displaysleep -> 0"
  fi
}

restore_display_sleep() {
  local saved
  [[ -f "$STATE_DIR/ac-display-sleep" ]] || return 0
  saved=$(cat "$STATE_DIR/ac-display-sleep" 2>/dev/null)
  [[ "$saved" == <-> ]] || saved=10
  set_ac_display_sleep "$saved"
  rm -f "$STATE_DIR/ac-display-sleep"
  log "AC displaysleep restored to $saved"
}

# 恢复全部设置。只有第一个参数是 Battery（pmset 明确报告电池供电）时，
# 才会在撤销 disablesleep 后检查盖子并睡眠；退出、注销、电源状态未知时都不睡。
restore_all() {
  restore_display_sleep
  if release_disablesleep && [[ "${1:-}" == "Battery" ]]; then
    sleep_if_lid_closed
  fi
  return 0
}

apply_once() {
  local cfg power enabled no_lock lid_awake app_running
  if ! cfg=$(config_path); then
    restore_all
    return 0
  fi
  # 读不到电源状态时这一轮什么都不改，免得插着电被误判成电池而睡眠。
  power=$(power_source) || return 0

  if [[ ! -f "$cfg" ]]; then
    restore_all "$power"
    return 0
  fi

  enabled=$(read_bool "$cfg" enabled false)
  no_lock=$(read_bool "$cfg" noLock false)
  lid_awake=$(read_bool "$cfg" lidAwake false)
  # App 退出时写 false：屏幕保护由 App 管，App 不在时显示器也恢复休眠，两者保持一致。
  app_running=$(read_bool "$cfg" appRunning true)

  if [[ "$enabled" != "true" || "$power" != "AC" ]]; then
    restore_all "$power"
    return 0
  fi

  if [[ "$no_lock" == "true" && "$app_running" == "true" ]]; then
    ensure_display_sleep_off
  else
    restore_display_sleep
  fi
  if [[ "$lid_awake" == "true" ]]; then
    acquire_disablesleep
  else
    release_disablesleep || true
  fi
}

if [[ "$ONCE" == "1" ]]; then
  apply_once
  exit 0
fi

SLEEP_PID=""
trap '[[ -n "$SLEEP_PID" ]] && kill "$SLEEP_PID" 2>/dev/null; restore_all; exit 0' TERM INT
trap 'restore_all' EXIT

while true; do
  apply_once
  # 后台 sleep + wait：收到 TERM 时 trap 立即执行，不用等 sleep 结束。
  sleep "$INTERVAL" &
  SLEEP_PID=$!
  wait "$SLEEP_PID"
  SLEEP_PID=""
done
