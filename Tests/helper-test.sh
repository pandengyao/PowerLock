#!/bin/zsh
# 助手逻辑测试：用 mock pmset / ioreg 验证各种电源、盖子和配置组合，不需要 root。
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MOCK="$TMP/mock"
STATE="$TMP/state"
mkdir -p "$MOCK"

cat > "$MOCK/pmset" <<'EOF'
#!/bin/zsh
set -u
STATE="${MOCK_STATE:?}"
echo "$*" >> "$STATE/invocations.log"
# 模拟 pmset 偶发失败
[[ "${1:-}" == "-g" && -z "${2:-}" && "${MOCK_FAIL_G:-0}" == "1" ]] && exit 1
[[ "${1:-}" == "-g" && "${2:-}" == "ps" && "${MOCK_FAIL_PS:-0}" == "1" ]] && exit 1
[[ "${1:-}" == "-a" && "${MOCK_FAIL_SET:-0}" == "1" ]] && exit 1
case "${1:-}" in
  -g)
    case "${2:-}" in
      ps|batt)
        if [[ "${MOCK_POWER:-AC}" == "AC" ]]; then
          echo "Now drawing from 'AC Power'"
        else
          echo "Now drawing from 'Battery Power'"
        fi
        # 接了 UPS 时，UPS 那行可能排在内置电池前面
        if [[ -n "${MOCK_UPS:-}" ]]; then
          echo " -Back-UPS (id=1234)	${MOCK_UPS}%; discharging; present: true"
        fi
        if [[ "${MOCK_BATTERY:-50}" != "none" ]]; then
          echo " -InternalBattery-0 (id=7209059)	${MOCK_BATTERY:-50}%; discharging; 2:00 remaining present: true"
        fi
        ;;
      custom)
        echo "Battery Power:"
        echo " displaysleep 10"
        echo "AC Power:"
        echo " displaysleep $(cat "$STATE/display" 2>/dev/null || echo 15)"
        ;;
      *)
        echo " SleepDisabled $(cat "$STATE/sleepdisabled" 2>/dev/null || echo 0)"
        # 带高功率模式的机型输出 powermode（1 = 低电量），其他机型输出 lowpowermode
        if [[ -n "${MOCK_POWERMODE:-}" ]]; then
          echo " powermode            ${MOCK_POWERMODE}"
        else
          echo " lowpowermode         ${MOCK_LPM:-0}"
        fi
        echo " displaysleep 0"
        ;;
    esac
    ;;
  -c)
    [[ "${2:-}" == "displaysleep" ]] && echo "${3:-0}" > "$STATE/display"
    ;;
  -a)
    [[ "${2:-}" == "disablesleep" ]] && echo "${3:-0}" > "$STATE/sleepdisabled"
    ;;
  sleepnow)
    echo yes > "$STATE/slept"
    ;;
esac
EOF

cat > "$MOCK/ioreg" <<'EOF'
#!/bin/zsh
echo '+-o IOPMrootDomain  <class IOPMrootDomain>'
echo '    {'
echo "      \"AppleClamshellCausesSleep\" = ${MOCK_CAUSES_SLEEP:-Yes}"
echo "      \"AppleClamshellState\" = ${MOCK_LID:-No}"
echo '    }'
EOF
cat > "$MOCK/sysctl" <<'EOF'
#!/bin/zsh
echo "${MOCK_BOOT:-BOOT-1}"
EOF
chmod +x "$MOCK/pmset" "$MOCK/ioreg" "$MOCK/sysctl"

FAILED=0

# 每个用例从干净状态开始：AC 显示器休眠 15 分钟，disablesleep 0，盖子打开。
reset() {
  rm -rf "$STATE"
  mkdir -p "$STATE"
  echo 15 > "$MOCK/display"
  echo 0 > "$MOCK/sleepdisabled"
  rm -f "$MOCK/slept" "$MOCK/invocations.log"
  MOCK_LID=No
  MOCK_CAUSES_SLEEP=Yes
  MOCK_BATTERY=50
  MOCK_LPM=0
  MOCK_UPS=""
  MOCK_POWERMODE=""
  MOCK_BOOT=BOOT-1
  rm -f "$TMP/helper.log"
}

write_config() {
  local enabled="$1" no_lock="$2" lid="$3" app_running="${4:-true}"
  local battery_lid="${5:-false}" floor="${6:-20}" until="${7:-0}"
  cat > "$TMP/config.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>enabled</key><${enabled}/>
  <key>noLock</key><${no_lock}/>
  <key>lidAwake</key><${lid}/>
  <key>appRunning</key><${app_running}/>
  <key>batteryLidAwake</key><${battery_lid}/>
  <key>batteryFloor</key><integer>${floor}</integer>
  <key>batteryLidUntil</key><integer>${until}</integer>
</dict>
</plist>
EOF
}

helper_env() {
  env POWERLOCK_PMSET="$MOCK/pmset" \
    POWERLOCK_IOREG="$MOCK/ioreg" \
    POWERLOCK_SYSCTL="$MOCK/sysctl" \
    POWERLOCK_LOG_FILE="$TMP/helper.log" \
    POWERLOCK_STATE_DIR="$STATE" \
    POWERLOCK_CONFIG="$TMP/config.plist" \
    MOCK_STATE="$MOCK" \
    MOCK_POWER="$1" \
    MOCK_LID="$MOCK_LID" \
    MOCK_CAUSES_SLEEP="$MOCK_CAUSES_SLEEP" \
    MOCK_BATTERY="$MOCK_BATTERY" \
    MOCK_LPM="$MOCK_LPM" \
    MOCK_UPS="$MOCK_UPS" \
    MOCK_POWERMODE="$MOCK_POWERMODE" \
    MOCK_BOOT="$MOCK_BOOT" \
    "${@:2}"
}

run_helper() {
  helper_env "$1" POWERLOCK_ONCE=1 /bin/zsh Resources/Helper/powerlock-helper.sh
}

# 模拟 launchd 停止助手（更新、重启、关机）：只执行退出时的恢复。
stop_helper() {
  helper_env "$1" POWERLOCK_EXIT_ONCE=1 /bin/zsh Resources/Helper/powerlock-helper.sh
}

expect() {
  local expected="$1" actual="$2" message="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok: $message"
  else
    echo "FAIL: $message (expected=$expected actual=$actual)" >&2
    FAILED=1
  fi
}

display()  { cat "$MOCK/display"; }
disabled() { cat "$MOCK/sleepdisabled"; }
slept()    { [[ -f "$MOCK/slept" ]] && echo yes || echo no; }
owned()    { [[ -f "$STATE/disablesleep-owned" ]] && echo yes || echo no; }

echo "# 插电 + 全部开启"
reset
write_config true true true
run_helper AC
expect 0 "$(display)" "AC: displaysleep -> 0"
expect 1 "$(disabled)" "AC: disablesleep -> 1"
expect 15 "$(cat "$STATE/ac-display-sleep")" "AC: 记住原 displaysleep"
expect yes "$(owned)" "AC: 记录 disablesleep 由 PowerLock 设置"

echo "# 盖子打开时拔电"
run_helper Battery
expect 0 "$(disabled)" "Battery: disablesleep -> 0"
expect 15 "$(display)" "Battery: displaysleep 恢复 15"
expect no "$([[ -f "$STATE/ac-display-sleep" ]] && echo yes || echo no)" "Battery: 清除保存值"
expect no "$(slept)" "Battery + 开盖: 不触发睡眠"

echo "# 合盖状态下拔电"
reset
write_config true true true
run_helper AC
MOCK_LID=Yes
run_helper Battery
expect 0 "$(disabled)" "合盖拔电: disablesleep -> 0"
expect yes "$(slept)" "合盖拔电: 立即睡眠"
rm -f "$MOCK/slept"
run_helper Battery
expect no "$(slept)" "合盖拔电: 下一轮不再重复 sleepnow"

echo "# 合盖 + 外接显示器时拔电"
reset
write_config true true true
run_helper AC
MOCK_LID=Yes
MOCK_CAUSES_SLEEP=No
run_helper Battery
expect 0 "$(disabled)" "外接显示器: disablesleep -> 0"
expect no "$(slept)" "外接显示器: 系统不因合盖睡眠，助手也不睡"

echo "# 插电但关闭功能"
reset
write_config false true true
run_helper AC
expect 0 "$(disabled)" "关闭功能: disablesleep 0"
expect 15 "$(display)" "关闭功能: displaysleep 不变"

echo "# 只开合盖运行"
reset
write_config true false true
run_helper AC
expect 1 "$(disabled)" "只开合盖: disablesleep 1"
expect 15 "$(display)" "只开合盖: displaysleep 不变"

echo "# 别的工具设置的 disablesleep 不碰"
reset
write_config true true false
run_helper AC
echo 1 > "$MOCK/sleepdisabled"
run_helper Battery
expect 1 "$(disabled)" "非 PowerLock 设置: 拔电后保持 1"
write_config true true true
run_helper AC
expect no "$(owned)" "非 PowerLock 设置: 开启合盖运行也不接管"
run_helper Battery
expect 1 "$(disabled)" "非 PowerLock 设置: 再次拔电仍保持 1"
expect no "$(slept)" "非 PowerLock 设置: 不触发睡眠"

echo "# 从 1.0.x 升级：安装脚本接管旧助手留下的 disablesleep"
reset
echo 1 > "$MOCK/sleepdisabled"
: > "$STATE/disablesleep-owned"
write_config true true true
run_helper Battery
expect 0 "$(disabled)" "升级: 旧版留下的 disablesleep 在电池下恢复 0"

echo "# 配置文件不存在"
reset
write_config true true true
run_helper AC
rm -f "$TMP/config.plist"
run_helper AC
expect 0 "$(disabled)" "无配置: disablesleep 0"
expect 15 "$(display)" "无配置: displaysleep 恢复"

echo "# pmset -g 偶发失败：保留标记，下一轮再撤销"
reset
write_config true true true
run_helper AC
MOCK_FAIL_G=1 run_helper Battery
expect yes "$(owned)" "读状态失败: 保留所有权标记"
expect 1 "$(disabled)" "读状态失败: 这一轮不改"
run_helper Battery
expect 0 "$(disabled)" "恢复后下一轮: disablesleep -> 0"
expect no "$(owned)" "恢复后下一轮: 删除标记"

echo "# pmset -a 失败：保留标记"
reset
write_config true true true
run_helper AC
MOCK_FAIL_SET=1 run_helper Battery
expect yes "$(owned)" "设置失败: 保留所有权标记"
run_helper Battery
expect 0 "$(disabled)" "设置失败后下一轮: disablesleep -> 0"

echo "# pmset -g ps 失败：插着电合着盖，不能当成电池去睡眠"
reset
write_config true true true
run_helper AC
MOCK_LID=Yes
MOCK_FAIL_PS=1 run_helper AC
expect 1 "$(disabled)" "电源未知: disablesleep 保持 1"
expect no "$(slept)" "电源未知: 不触发睡眠"

echo "# App 退出（appRunning=false）"
reset
write_config true true true
run_helper AC
write_config true true true false
run_helper AC
expect 15 "$(display)" "App 退出: displaysleep 恢复"
expect 1 "$(disabled)" "App 退出: 合盖运行继续生效"

echo "# 默认（没开用电池合盖）：拔电照常恢复，合着盖会睡"
reset
write_config true true true true false
run_helper AC
MOCK_LID=Yes
run_helper Battery
expect 0 "$(disabled)" "默认: 拔电后 disablesleep 0"
expect yes "$(slept)" "默认: 合着盖拔电立刻睡"

echo "# 电池合盖：开了开关，电量够，合着盖拔电也不睡"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
expect 1 "$(disabled)" "电池合盖: disablesleep 保持 1"
expect no "$(slept)" "电池合盖: 不触发睡眠"
expect 15 "$(display)" "电池合盖: 显示器休眠恢复系统设置"

echo "# 电池合盖：电量正好等于下限时继续，低于下限才停"
MOCK_BATTERY=20
run_helper Battery
expect 1 "$(disabled)" "等于下限: disablesleep 保持 1"
expect no "$(slept)" "等于下限: 不触发睡眠"

echo "# 电池合盖：电量低于下限，恢复睡眠并让合着盖的 Mac 睡下去"
MOCK_BATTERY=19
run_helper Battery
expect 0 "$(disabled)" "低于下限: disablesleep 0"
expect yes "$(slept)" "低于下限: 合着盖立刻睡"

echo "# 电池合盖：低于下限时插回电，插电行为照常"
rm -f "$MOCK/slept"
MOCK_BATTERY=15
run_helper AC
expect 1 "$(disabled)" "插回电: disablesleep 1"

echo "# 电池合盖：电量下限可调"
reset
write_config true true true true true 40 0
run_helper AC
MOCK_BATTERY=35
run_helper Battery
expect 0 "$(disabled)" "下限 40%、电量 35%: 恢复睡眠"

echo "# 电池合盖：下限超出范围时按默认 20% 处理"
reset
write_config true true true true true 1 0
run_helper AC
MOCK_BATTERY=18
run_helper Battery
expect 0 "$(disabled)" "下限填 1（不合法）、电量 18%: 按 20% 处理，恢复睡眠"

echo "# 电池合盖：低电量模式开着时恢复睡眠"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_BATTERY=80
MOCK_LPM=1
run_helper Battery
expect 0 "$(disabled)" "低电量模式: disablesleep 0"

echo "# 电池合盖：定时到期后恢复睡眠"
reset
write_config true true true true true 20 $(( $(date +%s) - 60 ))
run_helper AC
MOCK_BATTERY=80
MOCK_LID=Yes
run_helper Battery
expect 0 "$(disabled)" "定时已到: disablesleep 0"
expect yes "$(slept)" "定时已到: 合着盖立刻睡"

echo "# 电池合盖：定时没到继续运行"
reset
write_config true true true true true 20 $(( $(date +%s) + 3600 ))
run_helper AC
MOCK_BATTERY=80
run_helper Battery
expect 1 "$(disabled)" "定时没到: disablesleep 保持 1"

echo "# 电池合盖：读不到电量时按不允许处理"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_BATTERY=x
run_helper Battery
expect 0 "$(disabled)" "电量读不到: 恢复睡眠"

echo "# 电池合盖：只开了用电池合盖、没开合盖运行，不生效"
reset
write_config true true false true true 20 0
run_helper AC
MOCK_BATTERY=80
run_helper Battery
expect 0 "$(disabled)" "合盖运行关着: disablesleep 0"

echo "# 电池合盖：用电池时不接管别人打开的 disablesleep"
reset
write_config true true true true true 20 0
echo 1 > "$MOCK/sleepdisabled"
MOCK_BATTERY=80
run_helper Battery
expect no "$(owned)" "别人开的: 不接管"
MOCK_BATTERY=10
run_helper Battery
expect 1 "$(disabled)" "别人开的: 到下限也不关"

echo "# 电池合盖：接了 UPS 时只看内置电池的电量"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_UPS=95
MOCK_BATTERY=10
run_helper Battery
expect 0 "$(disabled)" "UPS 95%、内置 10%: 按内置电池恢复睡眠"

echo "# 电池合盖：没有内置电池（台式机接 UPS）时不生效"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_UPS=95
MOCK_BATTERY=none
run_helper Battery
expect 0 "$(disabled)" "没有内置电池: 恢复睡眠"

echo "# 电池合盖：带高功率模式的机型用 powermode 表示低电量模式"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_BATTERY=80
MOCK_POWERMODE=1
run_helper Battery
expect 0 "$(disabled)" "powermode 1: 恢复睡眠"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_BATTERY=80
MOCK_POWERMODE=2
run_helper Battery
expect 1 "$(disabled)" "powermode 2（高功率）: 继续运行"

echo "# 电池合盖：低电量模式触发时合着盖立刻睡"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_BATTERY=80
MOCK_LID=Yes
MOCK_LPM=1
run_helper Battery
expect 0 "$(disabled)" "低电量模式 + 合盖: disablesleep 0"
expect yes "$(slept)" "低电量模式 + 合盖: 立刻睡"

echo "# 电池合盖：停止以后合着盖不会被重新打开，开盖后才恢复"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=19
run_helper Battery
expect 0 "$(disabled)" "停止: disablesleep 0"
expect yes "$(slept)" "停止: 合着盖立刻睡"
rm -f "$MOCK/slept"
MOCK_BATTERY=21
run_helper Battery
expect 0 "$(disabled)" "后台短暂唤醒、电量回到 21%: 合着盖不重新打开"
expect no "$(slept)" "后台短暂唤醒: 不重复 sleepnow"
MOCK_LID=No
run_helper Battery
expect 1 "$(disabled)" "开盖以后: 重新打开"

echo "# 电池合盖：合着盖拔电时照常保持（拔电前已经打开）"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
expect 1 "$(disabled)" "合盖拔电: 保持 1"
run_helper Battery
expect 1 "$(disabled)" "合盖拔电后下一轮: 仍然保持 1"

echo "# 电池合盖：下限或定时不是整数类型"
write_typed_config() {
  cat > "$TMP/config.plist" <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>enabled</key><true/>
  <key>noLock</key><true/>
  <key>lidAwake</key><true/>
  <key>appRunning</key><true/>
  <key>batteryLidAwake</key><true/>
  $1
</dict>
</plist>
EOF2
}
reset
write_typed_config '<key>batteryFloor</key><string>5</string>'
run_helper AC
MOCK_BATTERY=15
run_helper Battery
expect 0 "$(disabled)" "下限是字符串 5: 按默认 20% 处理，15% 时恢复睡眠"
reset
write_typed_config "<key>batteryLidUntil</key><real>$(( $(date +%s) - 60 ))</real>"
run_helper AC
MOCK_BATTERY=80
run_helper Battery
expect 0 "$(disabled)" "定时是小数: 按已到期处理"
reset
write_typed_config '<key>batteryLidUntil</key><integer>9999999999</integer>'
run_helper AC
MOCK_BATTERY=80
run_helper Battery
expect 0 "$(disabled)" "定时超出范围: 按已到期处理"
reset
write_typed_config '<key>batteryLidUntil</key><string>0</string>'
run_helper AC
MOCK_BATTERY=80
run_helper Battery
expect 0 "$(disabled)" "定时是字符串 0: 按已到期处理，不当成不限时"
reset
write_typed_config ''
sed -i '' 's|<key>batteryLidAwake</key><true/>|<key>batteryLidAwake</key><string>true</string>|' "$TMP/config.plist"
run_helper AC
MOCK_BATTERY=80
run_helper Battery
expect 0 "$(disabled)" "开关是字符串 true: 按关闭处理"
reset
write_typed_config ''
run_helper AC
MOCK_BATTERY=80
run_helper Battery
expect 1 "$(disabled)" "没有定时这个键: 按不限时处理"

echo "# 电池合盖：下限或定时是数组、字典时按类型不对处理"
reset
write_typed_config "<key>batteryLidUntil</key><array><integer>0</integer></array>"
run_helper AC
MOCK_BATTERY=80
run_helper Battery
expect 0 "$(disabled)" "定时是数组: 按已到期处理"
reset
write_typed_config "<key>batteryLidUntil</key><dict><key>x</key><integer>0</integer></dict>"
run_helper AC
MOCK_BATTERY=80
run_helper Battery
expect 0 "$(disabled)" "定时是字典: 按已到期处理"
reset
write_typed_config "<key>batteryFloor</key><array><integer>5</integer></array>"
run_helper AC
MOCK_BATTERY=10
run_helper Battery
expect 0 "$(disabled)" "下限是数组: 按 20% 处理，10% 时恢复睡眠"

echo "# 电池合盖：停着的时候不每轮写日志"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_BATTERY=80
MOCK_LPM=1
for i in 1 2 3 4 5; do run_helper Battery; done
expect 1 "$(grep -c 'lid sleep restored' "$TMP/helper.log" 2>/dev/null || true)" "低电量模式连续 5 轮: 只记 1 次停止"

echo "# 电池合盖：注销后停在登录界面，合着盖会睡"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
expect 1 "$(disabled)" "注销前: 合盖保持 1"
no_user() {
  helper_env "$1" POWERLOCK_ONCE=1 POWERLOCK_CONFIG= POWERLOCK_CONSOLE_USER=root /bin/zsh Resources/Helper/powerlock-helper.sh
}
no_user Battery
expect 0 "$(disabled)" "注销后第一轮: disablesleep 0"
expect no "$(slept)" "注销后第一轮: 先不睡（可能正在关机）"
no_user Battery
expect yes "$(slept)" "注销后第二轮: 仍在登录界面、合着盖，补一次睡眠"
rm -f "$MOCK/slept"
no_user Battery
expect no "$(slept)" "注销后第三轮: 不重复睡眠"

echo "# 注销后很快又登录：交给正常逻辑，不补睡"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
no_user Battery
run_helper Battery
expect no "$(slept)" "重新登录: 条件满足时不睡"
expect 1 "$(disabled)" "重新登录: 接着保持 1"

echo "# 欠着睡眠时别的工具打开了 disablesleep：不替它睡"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
stop_helper Battery
echo 1 > "$MOCK/sleepdisabled"
MOCK_BATTERY=10
run_helper Battery
expect no "$(slept)" "别的工具打开了: 不睡"
expect 1 "$(disabled)" "别的工具打开了: 不动它"

echo "# 欠着睡眠时读不到盖子状态：开着盖不会被误睡"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
stop_helper Battery
MOCK_BATTERY=10
POWERLOCK_IOREG_FAIL=1
helper_env Battery POWERLOCK_ONCE=1 POWERLOCK_IOREG=/usr/bin/false /bin/zsh Resources/Helper/powerlock-helper.sh
expect no "$(slept)" "ioreg 读不到: 不睡"
expect yes "$([[ -f "$STATE/pending-lid-sleep" ]] && echo yes || echo no)" "ioreg 读不到: 保留记录下一轮再看"
run_helper Battery
expect yes "$(slept)" "ioreg 恢复后: 合着盖补睡"

echo "# 连续两次重启助手：第二次也能接着保持或补睡"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
stop_helper Battery
stop_helper Battery
MOCK_BATTERY=5
run_helper Battery
expect yes "$(slept)" "两次重启后电量低于下限: 补睡"

echo "# 电池合盖：助手在合盖运行时被重启，新助手接着保持"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
stop_helper Battery
expect 0 "$(disabled)" "助手退出: 撤销 disablesleep"
expect no "$(slept)" "助手退出: 退出时不睡（可能是关机）"
run_helper Battery
expect 1 "$(disabled)" "新助手启动: 同一次开机、条件满足，接着保持 1"
expect no "$(slept)" "新助手启动: 不睡"

echo "# 电池合盖：重启期间电量跌破下限，新助手补一次睡眠"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
stop_helper Battery
MOCK_BATTERY=10
run_helper Battery
expect 0 "$(disabled)" "低于下限: 保持 0"
expect yes "$(slept)" "低于下限: 补一次睡眠"
rm -f "$MOCK/slept"
run_helper Battery
expect no "$(slept)" "下一轮: 不重复睡眠"

echo "# 电池合盖：交接记录是上一次开机留下的，不接管"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
stop_helper Battery
MOCK_BOOT=BOOT-2
run_helper Battery
expect 0 "$(disabled)" "开机会话不同: 不重新打开"
expect no "$(slept)" "开机会话不同: 不睡"

echo "# 插电时助手退出不留交接记录"
reset
write_config true true true true true 20 0
MOCK_LID=Yes
run_helper AC
stop_helper AC
expect no "$([[ -f "$STATE/pending-lid-sleep" ]] && echo yes || echo no)" "插电退出: 没有交接记录"

echo "# 退出后插电再拔电：记录在插电时作废"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_LID=Yes
MOCK_BATTERY=80
run_helper Battery
stop_helper Battery
run_helper AC
expect no "$([[ -f "$STATE/pending-lid-sleep" ]] && echo yes || echo no)" "插电: 记录作废"
expect 1 "$(disabled)" "插电: 合盖运行 1"
MOCK_BATTERY=10
run_helper Battery
expect yes "$(slept)" "再拔电、低于下限: 正常 sleepnow"

echo "# 开着盖用电池时助手重启：接着保持，不睡"
reset
write_config true true true true true 20 0
run_helper AC
MOCK_BATTERY=80
run_helper Battery
stop_helper Battery
run_helper Battery
expect 1 "$(disabled)" "开盖重启: 接着保持"
expect no "$(slept)" "开盖重启: 不睡"
expect no "$([[ -f "$STATE/pending-lid-sleep" ]] && echo yes || echo no)" "开盖重启: 记录已清"

echo "# 选项关着时用电池退出：不留记录"
reset
write_config true true true true false 20 0
run_helper AC
MOCK_LID=Yes
run_helper Battery
stop_helper Battery
expect no "$([[ -f "$STATE/pending-lid-sleep" ]] && echo yes || echo no)" "选项关着: 没有记录"

echo "# 收到 TERM 立即恢复并退出（盖子合着也不睡）"
reset
write_config true true true
run_helper AC
# 直接后台启动 env（不用 helper_env 函数），$! 才是助手进程本身，而不是函数的子 shell。
env POWERLOCK_PMSET="$MOCK/pmset" POWERLOCK_IOREG="$MOCK/ioreg" \
  POWERLOCK_STATE_DIR="$STATE" POWERLOCK_CONFIG="$TMP/config.plist" \
  POWERLOCK_INTERVAL=60 MOCK_STATE="$MOCK" MOCK_POWER=AC MOCK_LID=Yes \
  /bin/zsh Resources/Helper/powerlock-helper.sh &
pid=$!
sleep 1
start=$SECONDS
kill -TERM $pid
wait $pid || true
expect yes "$( (( SECONDS - start < 3 )) && echo yes || echo no )" "TERM: 3 秒内退出"
expect 0 "$(disabled)" "TERM: disablesleep 恢复 0"
expect 15 "$(display)" "TERM: displaysleep 恢复"
expect no "$(slept)" "TERM: 退出时不触发睡眠"

if (( FAILED )); then
  echo "HELPER TESTS FAILED" >&2
  exit 1
fi
echo "ALL HELPER TESTS PASSED"
