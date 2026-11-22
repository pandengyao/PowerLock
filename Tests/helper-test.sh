#!/bin/zsh
# 助手逻辑冒烟测试：用 mock pmset 验证 AC/电池/关闭三种状态，不需要 root。
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/mock" "$TMP/state"
echo 15 > "$TMP/mock/display"
echo 0 > "$TMP/mock/sleepdisabled"

cat > "$TMP/mock/pmset" <<'MOCK'
#!/bin/zsh
set -u
STATE="${MOCK_STATE:?}"
echo "$*" >> "$STATE/invocations.log"
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
        if [[ "$(cat "$STATE/sleepdisabled" 2>/dev/null || echo 0)" == "1" ]]; then
          echo " SleepDisabled 1"
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
esac
MOCK
chmod +x "$TMP/mock/pmset"

write_config() {
  local enabled="$1" no_lock="$2" lid="$3"
  cat > "$TMP/config.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>enabled</key><${enabled}/>
  <key>noLock</key><${no_lock}/>
  <key>lidAwake</key><${lid}/>
</dict>
</plist>
EOF
}

run_helper() {
  POWERLOCK_PMSET="$TMP/mock/pmset" \
  POWERLOCK_STATE_DIR="$TMP/state" \
  POWERLOCK_CONFIG="$TMP/config.plist" \
  POWERLOCK_ONCE=1 \
  MOCK_STATE="$TMP/mock" \
  MOCK_POWER="$1" \
  /bin/zsh Resources/Helper/powerlock-helper.sh
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $message (expected=$expected actual=$actual)" >&2
    exit 1
  fi
  echo "ok: $message"
}

# 1. AC + 启用 -> displaysleep 0, disablesleep 1, 记住原值 15
echo 15 > "$TMP/mock/display"
echo 0 > "$TMP/mock/sleepdisabled"
write_config true true true
run_helper AC
assert_eq "0" "$(cat "$TMP/mock/display")" "AC: displaysleep -> 0"
assert_eq "1" "$(cat "$TMP/mock/sleepdisabled")" "AC: disablesleep -> 1"
assert_eq "15" "$(cat "$TMP/state/ac-display-sleep")" "AC: 记住原 displaysleep"

# 2. 拔电 -> 恢复 disablesleep 0 与原 displaysleep
run_helper Battery
assert_eq "0" "$(cat "$TMP/mock/sleepdisabled")" "Battery: disablesleep -> 0"
assert_eq "15" "$(cat "$TMP/mock/display")" "Battery: displaysleep 恢复 15"
[[ ! -f "$TMP/state/ac-display-sleep" ]] && echo "ok: 电池状态清除保存值"

# 3. 插电但关闭功能 -> 保持恢复
echo 15 > "$TMP/mock/display"
echo 0 > "$TMP/mock/sleepdisabled"
write_config false true true
run_helper AC
assert_eq "0" "$(cat "$TMP/mock/sleepdisabled")" "disabled: disablesleep 0"
assert_eq "15" "$(cat "$TMP/mock/display")" "disabled: displaysleep 不变"

# 4. 只有 lidAwake、没有 noLock -> 不动 displaysleep
echo 15 > "$TMP/mock/display"
echo 0 > "$TMP/mock/sleepdisabled"
write_config true false true
run_helper AC
assert_eq "1" "$(cat "$TMP/mock/sleepdisabled")" "lid only: disablesleep 1"
assert_eq "15" "$(cat "$TMP/mock/display")" "lid only: displaysleep 不变"

# 5. 配置文件不存在 -> 恢复默认
rm -f "$TMP/config.plist"
echo 0 > "$TMP/mock/display"
echo 1 > "$TMP/mock/sleepdisabled"
run_helper AC
assert_eq "0" "$(cat "$TMP/mock/sleepdisabled")" "no config: disablesleep 0"

echo "ALL HELPER TESTS PASSED"
