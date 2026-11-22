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
      ps)
        if [[ "${MOCK_POWER:-AC}" == "AC" ]]; then
          echo "Now drawing from 'AC Power'"
        else
          echo "Now drawing from 'Battery Power'"
        fi
        echo " -InternalBattery-0 50%; discharging; 2:00 remaining present: true"
        ;;
      custom)
        echo "Battery Power:"
        echo " displaysleep 10"
        echo "AC Power:"
        echo " displaysleep $(cat "$STATE/display" 2>/dev/null || echo 15)"
        ;;
      *)
        echo " SleepDisabled $(cat "$STATE/sleepdisabled" 2>/dev/null || echo 0)"
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
chmod +x "$MOCK/pmset" "$MOCK/ioreg"

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
}

write_config() {
  local enabled="$1" no_lock="$2" lid="$3" app_running="${4:-true}"
  cat > "$TMP/config.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>enabled</key><${enabled}/>
  <key>noLock</key><${no_lock}/>
  <key>lidAwake</key><${lid}/>
  <key>appRunning</key><${app_running}/>
</dict>
</plist>
EOF
}

helper_env() {
  env POWERLOCK_PMSET="$MOCK/pmset" \
    POWERLOCK_IOREG="$MOCK/ioreg" \
    POWERLOCK_STATE_DIR="$STATE" \
    POWERLOCK_CONFIG="$TMP/config.plist" \
    MOCK_STATE="$MOCK" \
    MOCK_POWER="$1" \
    MOCK_LID="$MOCK_LID" \
    MOCK_CAUSES_SLEEP="$MOCK_CAUSES_SLEEP" \
    "${@:2}"
}

run_helper() {
  helper_env "$1" POWERLOCK_ONCE=1 /bin/zsh Resources/Helper/powerlock-helper.sh
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
