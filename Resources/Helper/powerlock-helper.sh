#!/bin/zsh
# PowerLock 后台助手（以 root 运行）
#
# 由 launchd 启动，每 5 秒检查一次电源状态，只执行固定的 pmset 命令：
#   - 插电 + 开启「插电不锁屏」：AC 显示器不休眠（displaysleep 0）
#   - 插电 + 开启「合盖后保持运行」：disablesleep 1
#   - 电池 / 关闭功能：恢复 disablesleep 0 与原来的 AC 显示器休眠时间
#
# 配置由 PowerLock.app 写入（仅布尔值），本脚本不会执行用户传入的命令。

set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

readonly LABEL="com.powerlock.helper"
STATE_DIR="${POWERLOCK_STATE_DIR:-/Library/Application Support/PowerLock}"
PMSET="${POWERLOCK_PMSET:-/usr/bin/pmset}"
CONFIG_OVERRIDE="${POWERLOCK_CONFIG:-}"
ONCE="${POWERLOCK_ONCE:-0}"
INTERVAL="${POWERLOCK_INTERVAL:-5}"

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

config_path() {
  if [[ -n "$CONFIG_OVERRIDE" ]]; then
    print -r -- "$CONFIG_OVERRIDE"
    return 0
  fi
  local user home
  user=$(console_user) || return 1
  home=$(user_home "$user") || return 1
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

is_on_ac() {
  [[ "$("$PMSET" -g ps 2>/dev/null | head -n 1)" == *"AC Power"* ]]
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

disablesleep_state() {
  local value
  value=$("$PMSET" -g 2>/dev/null | awk '/SleepDisabled/{print $2; exit}')
  if [[ "$value" == "1" ]]; then
    print -r -- "1"
  else
    print -r -- "0"
  fi
}

set_disablesleep() {
  [[ "$(disablesleep_state)" == "$1" ]] && return 0
  if "$PMSET" -a disablesleep "$1" >/dev/null 2>&1; then
    log "disablesleep -> $1"
  fi
}

ensure_display_sleep_off() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  if [[ ! -f "$STATE_DIR/ac-display-sleep" ]]; then
    print -r -- "$(current_ac_display_sleep)" > "$STATE_DIR/ac-display-sleep" 2>/dev/null || true
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

restore_all() {
  set_disablesleep 0
  restore_display_sleep
}

apply_once() {
  local cfg enabled no_lock lid_awake
  cfg=$(config_path) || { restore_all; return 0; }
  if [[ ! -f "$cfg" ]]; then
    restore_all
    return 0
  fi

  enabled=$(read_bool "$cfg" enabled false)
  no_lock=$(read_bool "$cfg" noLock false)
  lid_awake=$(read_bool "$cfg" lidAwake false)

  if [[ "$enabled" != "true" ]]; then
    restore_all
    return 0
  fi

  if is_on_ac; then
    if [[ "$no_lock" == "true" ]]; then
      ensure_display_sleep_off
    else
      restore_display_sleep
    fi
    if [[ "$lid_awake" == "true" ]]; then
      set_disablesleep 1
    else
      set_disablesleep 0
    fi
  else
    set_disablesleep 0
    restore_display_sleep
  fi
}

if [[ "$ONCE" == "1" ]]; then
  apply_once
  exit 0
fi

trap 'restore_all; exit 0' TERM INT
trap 'restore_all' EXIT

while true; do
  apply_once
  sleep "$INTERVAL"
done
