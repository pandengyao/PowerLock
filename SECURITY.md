# 安全说明

PowerLock 会在首次启用时安装一个以 root 身份运行的 launchd 后台助手。这份文档说明它做什么、装在哪里、如何验证和删除。

## 助手做什么

助手文件：`/Library/PrivilegedHelperTools/com.powerlock.helper`（root:wheel，755）
launchd 配置：`/Library/LaunchDaemons/com.powerlock.helper.plist`（root:wheel，644）

它只执行以下几类固定命令，不接收命令行参数、不执行用户输入：

- `pmset -c displaysleep 0` / `pmset -c displaysleep <恢复值>`
- `pmset -a disablesleep 1` / `pmset -a disablesleep 0`
- `pmset sleepnow`：只在用电池、`disablesleep` 是 0、盖子合着、而且系统此刻本该因合盖睡眠时执行一次。两种情况：PowerLock 刚把自己打开的 `disablesleep` 改回 0；或者之前改回 0 时不能马上睡（见下面的 `pending-lid-sleep`）
- `pmset -g`、`pmset -g ps`、`pmset -g batt`、`pmset -g custom`、`ioreg -r -k AppleClamshellState`、`sysctl -n kern.bootsessionuuid`、`dscl -plist . -read /Users/<控制台用户> NFSHomeDirectory`（只读查询；`-g batt` 只读内置电池那一行的电量，`-g` 里的 `lowpowermode`，或带高功率模式机型上的 `powermode`，用来判断低电量模式）

状态文件在 `/Library/Application Support/PowerLock`（root 所有）：

- `ac-display-sleep`：改动前的插电显示器休眠时间，用于恢复
- `disablesleep-owned`：表示 `disablesleep` 是 PowerLock 打开的；没有这个文件时，助手不会关闭别人打开的 `disablesleep`
- `pending-lid-sleep`：PowerLock 在用电池时撤销了自己打开的 `disablesleep`，但当时不能马上 `sleepnow` 留下的记录：助手被停止（更新、重启、关机），或者没有登录用户（注销，也可能正在关机）。内容是这次开机的 `kern.bootsessionuuid`，只用来做字符串比较。之后同一次开机里：用电池合盖运行的条件仍满足就接着保持；否则在用电池、`disablesleep` 仍为 0、盖子确实合着时执行一次 `sleepnow`。插电、开盖、换了开机会话，或者别的工具打开了 `disablesleep`，都只删除记录，不睡

它读取的配置只有布尔值和整数，来自当前控制台用户的：

`~/Library/Application Support/PowerLock/config.plist`

配置由 PowerLock.app 写入，字段：

- `enabled`：功能总开关
- `noLock`：插电时保持屏幕常亮
- `lidAwake`：插电时合盖保持运行
- `appRunning`：App 是否在运行；App 退出时为 false，助手据此恢复显示器休眠
- `batteryLidAwake`：用电池时也合盖运行（默认 false，需要 `lidAwake` 也为 true）
- `batteryFloor`：整数，电量低于这个百分比就恢复睡眠；只接受 5～90，类型或范围不对时按 20 处理
- `batteryLidUntil`：整数，用电池合盖运行的截止时间（Unix 秒），0 或没有这个键表示不限时；类型不对或不在 0～4102444800 之间时按已到期处理

用电池时，只有 `enabled`、`lidAwake`、`batteryLidAwake` 都为 true，内置电池电量读得到且不低于 `batteryFloor`，没开低电量模式，也没过 `batteryLidUntil`，助手才保持 `disablesleep 1`；任何一项不满足或读不到，都按用电池的默认行为恢复睡眠。停止以后，盖子合着时助手不会重新打开 `disablesleep`，要开盖或插电。

## 不做什么

- 除手动「检查更新」请求 GitHub Releases API 外，不联网、不上传数据
- 不读取用户文件内容
- 不监听端口
- 不执行配置中的任何字符串（只读取布尔值和整数）

## 如何验证

```bash
sudo plutil -p /Library/LaunchDaemons/com.powerlock.helper.plist
sudo cat /Library/PrivilegedHelperTools/com.powerlock.helper
sudo launchctl print system/com.powerlock.helper
```

源码中的助手脚本：`Resources/Helper/powerlock-helper.sh`，安装脚本：`Resources/Helper/install-helper.sh`。

## 已知权限边界

配置文件位于用户目录，属于当前用户可写。也就是说，任何以该用户身份运行的进程都可以开关 PowerLock 的功能（效果仅限于切换睡眠/屏幕常亮，包括用电池时合盖运行；电量下限和低电量模式的检查仍然生效，不能借此获得 root）。这是本工具刻意的取舍：避免每次切换都弹管理员授权。

助手只读取布尔值和整数，用 `plutil -extract` 解析。布尔值只认 `<true/>`/`<false/>`；整数先用 `plutil -type` 确认是 `<integer>`（字符串、小数、数组、字典都不算），最多 10 位，并检查范围。配置内容不会被当作命令或路径使用。

## 下载校验

每个 Release 都附带 `SHA256SUMS.txt`，并由 GitHub Actions 生成构建来源证明（build provenance），可以确认安装包是由本仓库的 CI 构建的：

```bash
shasum -a 256 -c SHA256SUMS.txt
gh attestation verify PowerLock-<版本>.dmg -R pandengyao/PowerLock
```

## 删除

优先使用 App 菜单中的「更多 → 卸载 PowerLock…」。手动删除见 README 的卸载章节。

## 报告安全问题

请通过 GitHub Security Advisory 或邮件私下联系维护者，不要在公开 Issue 中披露细节。
