#!/bin/zsh
# PowerLock 后台助手（以 root 运行）
#
# 由 launchd 启动，每 5 秒检查一次电源状态，只执行固定的 pmset 命令：
#   - 插电 + 开启「插电不锁屏」+ App 在运行：AC 显示器不休眠（displaysleep 0）
#   - 插电 + 开启「合盖后保持运行」：disablesleep 1
#   - 电池 + 开启「用电池时也合盖运行」：disablesleep 保持 1，直到电量低于下限、
#     开了低电量模式、到了定时关闭的时间，或读不到电量（下限和定时可以在 App 里设置）。
#     用电池且盖子合着时只保持、不新打开：停止过一次以后，要开盖或插电才会恢复
#   - 其他情况（电池且没开上面的选项 / 关闭功能）：恢复 disablesleep 0 与原来的 AC 显示器休眠时间；
#     如果是拔电或触发了保护、而且盖子已经合上，按系统规则立即睡眠（pmset sleepnow）
#
# 配置由 PowerLock.app 写入：布尔值只认 true/false，整数只认 plist 的 <integer> 并检查范围。本脚本不会执行用户传入的命令。

set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

# 助手逻辑有变化时加 1。App 会比较内置版本和已安装版本，提示用户更新助手。
readonly HELPER_VERSION=3
readonly LABEL="com.powerlock.helper"
STATE_DIR="${POWERLOCK_STATE_DIR:-/Library/Application Support/PowerLock}"
PMSET="${POWERLOCK_PMSET:-/usr/bin/pmset}"
IOREG="${POWERLOCK_IOREG:-/usr/sbin/ioreg}"
SYSCTL="${POWERLOCK_SYSCTL:-/usr/sbin/sysctl}"
CONFIG_OVERRIDE="${POWERLOCK_CONFIG:-}"
ONCE="${POWERLOCK_ONCE:-0}"
INTERVAL="${POWERLOCK_INTERVAL:-5}"

# disablesleep 是 PowerLock 设置的才由 PowerLock 撤销，不影响别的工具或手动设置。
OWNED_FLAG="$STATE_DIR/disablesleep-owned"
# PowerLock 撤销了自己打开的 disablesleep，但当时不能立刻 sleepnow（助手退出、没有登录用户），
# 记下这次开机的会话 ID，之后在同一次开机里、用电池且盖子确实合着时补一次睡眠。
PENDING="$STATE_DIR/pending-lid-sleep"

log() {
  # 测试时写到文件里，方便检查
  if [[ -n "${POWERLOCK_LOG_FILE:-}" ]]; then
    print -r -- "$*" >> "$POWERLOCK_LOG_FILE"
    return 0
  fi
  logger -t "$LABEL" -- "$*" 2>/dev/null
}

console_user() {
  if [[ -n "${POWERLOCK_CONSOLE_USER:-}" ]]; then
    print -r -- "$POWERLOCK_CONSOLE_USER"
    return 0
  fi
  stat -f %Su /dev/console 2>/dev/null
}

user_home() {
  local user="$1"
  [[ -z "$user" || "$user" == "root" || "$user" == "loginwindow" ]] && return 1
  local home
  # 用 plist 输出：值里有空格时 dscl 的文本输出会换行，按列取会取错
  home=$(dscl -plist . -read "/Users/$user" NFSHomeDirectory 2>/dev/null \
    | plutil -extract 'dsAttrTypeStandard:NFSHomeDirectory.0' raw -o - - 2>/dev/null) || return 1
  [[ "$home" == /* && "$home" != *$'\n'* ]] || return 1
  print -r -- "$home"
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

# 读一个布尔配置：只认 plist 的 <true/> / <false/>，其他类型（字符串 "true"、整数 1）都按默认值。
read_bool() {
  local file="$1" key="$2" fallback="$3" value
  value=$(plutil -extract "$key" raw -expect bool -o - "$file" 2>/dev/null) || value=""
  if [[ "$value" == "true" ]]; then
    print -r -- "true"
  elif [[ "$value" == "false" ]]; then
    print -r -- "false"
  else
    print -r -- "$fallback"
  fi
}

# 读一个整数配置。配置文件用户可写，必须校验：只认 plist 的 <integer>（字符串、小数、布尔值、
# 数组、字典、UID 都不算），最多 10 位，并且在 [min, max] 范围内。
# 返回 0 并输出值；键不存在或文件读不了返回 2；类型或范围不对返回 1。
read_int() {
  local file="$1" key="$2" min="$3" max="$4" type value
  type=$(plutil -type "$key" "$file" 2>/dev/null) || return 2
  [[ "$type" == "integer" ]] || return 1
  value=$(plutil -extract "$key" raw -expect integer -o - "$file" 2>/dev/null) || return 1
  [[ "$value" == <-> && ${#value} -le 10 ]] || return 1
  (( value >= min && value <= max )) || return 1
  print -r -- "$value"
}

# 内置电池的电量百分比；没有内置电池（台式机接 UPS）或读不到时返回失败。
# 只看 InternalBattery 那一行，接了 UPS 时不会读成 UPS 的电量。
battery_percent() {
  local out line pct
  out=$("$PMSET" -g batt 2>/dev/null) || return 1
  line=$(print -r -- "$out" | grep -e '-InternalBattery-' | head -n 1)
  [[ -n "$line" ]] || return 1
  pct=$(print -r -- "$line" | grep -o '[0-9]\{1,3\}%' | head -n 1)
  pct=${pct%\%}
  [[ "$pct" == <-> ]] && (( pct <= 100 )) || return 1
  print -r -- "$pct"
}

# 低电量模式是否开着。一般机型输出 lowpowermode；带高功率模式的机型输出 powermode，1 表示低电量。
# pmset 读失败时按"开着"处理，宁可让 Mac 睡下去。
low_power_mode() {
  local out
  out=$("$PMSET" -g 2>/dev/null) || return 0
  print -r -- "$out" | awk '($1=="lowpowermode" || $1=="powermode") && $2=="1" {found=1} END {exit !found}'
}

# 用电池时是否允许合盖运行。
# 要求：开关打开，电量读得到且不低于下限，没开低电量模式，没超过定时关闭的时间。
# 任何一项读不到都按"不允许"处理，宁可让 Mac 睡下去。
# 不允许时把原因写进 STOP_REASON；只在真正撤销 disablesleep 时记日志，免得停着时每 5 秒写一条。
STOP_REASON=""
battery_lid_allowed() {
  local cfg="$1" floor deadline rc pct
  STOP_REASON=""
  [[ "$(read_bool "$cfg" batteryLidAwake false)" == "true" ]] || return 1
  # 下限不合法时按默认 20%
  floor=$(read_int "$cfg" batteryFloor 5 90) || floor=20
  pct=$(battery_percent) || { STOP_REASON="battery level unreadable"; return 1; }
  (( pct >= floor )) || { STOP_REASON="battery ${pct}% < floor ${floor}%"; return 1; }
  low_power_mode && { STOP_REASON="low power mode on (or unreadable)"; return 1; }
  # 没有这个键表示不限时；有但不合法时按已到期处理，不能变成不限时
  deadline=$(read_int "$cfg" batteryLidUntil 0 4102444800)
  rc=$?
  if (( rc == 2 )); then
    deadline=0
  elif (( rc != 0 )); then
    STOP_REASON="battery lid timer invalid, treated as expired"
    return 1
  fi
  if (( deadline > 0 )) && (( $(date +%s) >= deadline )); then
    STOP_REASON="battery lid timer expired"
    return 1
  fi
  return 0
}

# 盖子合着、而且系统会因合盖而睡眠（没接外接显示器）时返回 0；ioreg 读不到返回 1。
lid_closed_sleeping() {
  local lid
  lid=$("$IOREG" -r -k AppleClamshellState -d 1 2>/dev/null) || return 1
  [[ "$lid" == *'"AppleClamshellState" = Yes'* && "$lid" == *'"AppleClamshellCausesSleep" = Yes'* ]]
}

# 用电池时保持合盖运行：PowerLock 已经打开的 disablesleep 继续保持；
# 要新打开时，盖子合着就不打开。这样因为电量低、低电量模式、定时或读不到电量停止过一次以后，
# 合着盖的 Mac 在后台短暂唤醒时不会被重新打开，要等开盖或插电。
keep_disablesleep_on_battery() {
  local current
  if [[ -f "$OWNED_FLAG" ]]; then
    current=$(disablesleep_state) || return 0
    [[ "$current" == "1" ]] && return 0
  fi
  # 盖子合着或读不到盖子状态时都不新打开
  "$IOREG" -r -k AppleClamshellState -d 1 >/dev/null 2>&1 || return 0
  lid_closed_sleeping && return 0
  acquire_disablesleep
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
  if release_disablesleep; then
    [[ -n "$STOP_REASON" ]] && log "$STOP_REASON, lid sleep restored"
    [[ "${1:-}" == "Battery" ]] && sleep_if_lid_closed
  fi
  STOP_REASON=""
  return 0
}

boot_session() {
  "$SYSCTL" -n kern.bootsessionuuid 2>/dev/null
}

# 记下"欠一次睡眠"。只在 PowerLock 刚撤销了自己打开的 disablesleep、而且明确在用电池时调用。
mark_pending_sleep() {
  local session
  session=$(boot_session) || return 0
  [[ -n "$session" ]] || return 0
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  print -r -- "$session" > "$PENDING" 2>/dev/null || true
}

# 欠着一次睡眠时，在同一次开机里、用电池、盖子确实合着、disablesleep 已经是 0 时补上。
# 插电、开盖、换了开机会话时只删记录不睡。读不到状态时保留记录，下一轮再看。
settle_pending_sleep() {
  local power="$1" saved current
  [[ -f "$PENDING" ]] || return 0
  saved=$(cat "$PENDING" 2>/dev/null)
  if [[ -z "$saved" || "$saved" != "$(boot_session)" || "$power" == "AC" ]]; then
    rm -f "$PENDING"
    return 0
  fi
  [[ "$power" == "Battery" ]] || return 0
  current=$(disablesleep_state) || return 0
  # 别的工具（或用户）在这期间打开了 disablesleep：不替它决定睡不睡
  if [[ "$current" != "0" ]]; then
    rm -f "$PENDING"
    return 0
  fi
  "$IOREG" -r -k AppleClamshellState -d 1 >/dev/null 2>&1 || return 0
  rm -f "$PENDING"
  if lid_closed_sleeping; then
    log "lid still closed on battery after helper restart or logout, sleeping now"
    "$PMSET" sleepnow >/dev/null 2>&1 || true
  fi
}

# 助手退出（更新、重启、关机）时调用：撤销 disablesleep，但不 sleepnow（可能是关机或注销）。
# 正在用电池时记下"欠一次睡眠"，由下一次启动的助手决定接着保持还是补睡。
restore_on_exit() {
  local power
  restore_display_sleep
  if release_disablesleep; then
    power=$(power_source) || power=""
    [[ "$power" == "Battery" ]] && mark_pending_sleep
  fi
  STOP_REASON=""
}

# 欠着一次睡眠、而且用电池合盖运行的条件仍然满足：接着保持，不睡。成功打开后才删记录。
resume_after_restart() {
  local cfg="$1" power="$2" enabled="$3" lid_awake="$4"
  [[ -f "$PENDING" && "$power" == "Battery" ]] || return 1
  [[ "$(cat "$PENDING" 2>/dev/null)" == "$(boot_session)" ]] || return 1
  [[ "$enabled" == "true" && "$lid_awake" == "true" ]] || return 1
  battery_lid_allowed "$cfg" || return 1
  [[ "$(disablesleep_state)" == "0" ]] || return 1
  acquire_disablesleep
  [[ "$(disablesleep_state)" == "1" && -f "$OWNED_FLAG" ]] || return 1
  rm -f "$PENDING"
  log "battery lid mode resumed after helper restart"
  return 0
}

apply_once() {
  local cfg power enabled no_lock lid_awake app_running
  if ! cfg=$(config_path); then
    # 没有登录用户（注销后停在登录界面，也可能正在关机）：这一轮只撤销、不睡，记下欠一次睡眠；
    # 下一轮还是没有登录用户、仍在用电池且盖子合着时再补。关机时 launchd 会先停掉助手。
    power=$(power_source) || power=""
    if [[ -f "$PENDING" ]]; then
      settle_pending_sleep "$power"
    else
      restore_display_sleep
      if release_disablesleep; then
        log "no console user, lid sleep restored"
        [[ "$power" == "Battery" ]] && mark_pending_sleep
      fi
    fi
    return 0
  fi
  # 读不到电源状态时这一轮什么都不改，免得插着电被误判成电池而睡眠。
  power=$(power_source) || return 0

  if [[ ! -f "$cfg" ]]; then
    restore_all "$power"
    settle_pending_sleep "$power"
    return 0
  fi

  enabled=$(read_bool "$cfg" enabled false)
  no_lock=$(read_bool "$cfg" noLock false)
  lid_awake=$(read_bool "$cfg" lidAwake false)
  # App 退出时写 false：屏幕保护由 App 管，App 不在时显示器也恢复休眠，两者保持一致。
  app_running=$(read_bool "$cfg" appRunning true)

  resume_after_restart "$cfg" "$power" "$enabled" "$lid_awake" && return 0

  if [[ "$enabled" != "true" ]]; then
    restore_all "$power"
    settle_pending_sleep "$power"
    return 0
  fi

  # 用电池时：显示器休眠一律恢复系统设置（不锁屏只在插电时生效）；
  # 合盖运行只在用户打开了「用电池时也合盖运行」且没触发任何保护时保留。
  if [[ "$power" != "AC" ]]; then
    restore_display_sleep
    if [[ "$lid_awake" == "true" ]] && battery_lid_allowed "$cfg"; then
      keep_disablesleep_on_battery
    else
      restore_all "$power"
    fi
    settle_pending_sleep "$power"
    return 0
  fi

  # 插电：欠着的睡眠作废
  settle_pending_sleep "$power"

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
# 测试用：只执行一次退出时的恢复（模拟 launchd 停止助手）
if [[ "${POWERLOCK_EXIT_ONCE:-0}" == "1" ]]; then
  restore_on_exit
  exit 0
fi

SLEEP_PID=""
trap '[[ -n "$SLEEP_PID" ]] && kill "$SLEEP_PID" 2>/dev/null; restore_on_exit; trap - EXIT; exit 0' TERM INT
trap 'restore_on_exit' EXIT

while true; do
  apply_once
  # 后台 sleep + wait：收到 TERM 时 trap 立即执行，不用等 sleep 结束。
  sleep "$INTERVAL" &
  SLEEP_PID=$!
  wait "$SLEEP_PID"
  SLEEP_PID=""
done
