# 安全说明

PowerLock 会在首次启用时安装一个以 root 身份运行的 launchd 后台助手。这份文档说明它做什么、装在哪里、如何验证和删除。

## 助手做什么

助手文件：`/Library/PrivilegedHelperTools/com.powerlock.helper`（root:wheel，755）
launchd 配置：`/Library/LaunchDaemons/com.powerlock.helper.plist`（root:wheel，644）

它只执行以下几类固定命令，不接收命令行参数、不执行用户输入：

- `pmset -c displaysleep 0` / `pmset -c displaysleep <恢复值>`
- `pmset -a disablesleep 1` / `pmset -a disablesleep 0`
- `pmset -g`、`pmset -g ps`、`pmset -g custom`（只读查询）

它读取的配置只有布尔值，来自当前控制台用户的：

`~/Library/Application Support/PowerLock/config.plist`

配置由 PowerLock.app 写入，字段：

- `enabled`：功能总开关
- `noLock`：插电时保持屏幕常亮
- `lidAwake`：插电时合盖保持运行

## 不做什么

- 除手动「检查更新」请求 GitHub Releases API 外，不联网、不上传数据
- 不读取用户文件内容
- 不监听端口
- 不执行配置中的任何字符串（只读取布尔值）

## 如何验证

```bash
sudo plutil -p /Library/LaunchDaemons/com.powerlock.helper.plist
sudo cat /Library/PrivilegedHelperTools/com.powerlock.helper
sudo launchctl print system/com.powerlock.helper
```

源码中的助手脚本：`Resources/Helper/powerlock-helper.sh`，安装脚本：`Resources/Helper/install-helper.sh`。

## 已知权限边界

配置文件位于用户目录，属于当前用户可写。也就是说，任何以该用户身份运行的进程都可以开关 PowerLock 的功能（效果仅限于切换睡眠/屏幕常亮，不能借此获得 root）。这是本工具刻意的取舍：避免每次切换都弹管理员授权。

## 删除

优先使用 App 菜单中的「卸载后台助手…」。手动删除见 README 的卸载章节。

## 报告安全问题

请通过 GitHub Security Advisory 或邮件私下联系维护者，不要在公开 Issue 中披露细节。
