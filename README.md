# PowerLock

> 插电时保持屏幕常亮、不自动锁屏；合盖后继续运行。拔电或关闭功能后自动恢复系统默认。

<p align="center"><img src="docs/images/icon.png" width="128" alt="PowerLock icon"></p>

PowerLock 是一个 macOS 菜单栏小工具，适合把笔记本当台式机用、需要长时间保持在线的人：

- **插电不锁屏**：屏幕不会因为屏幕保护程序 / 显示器休眠而自动锁定
- **合盖后保持运行**：插电时合上盖子，后台任务、下载、远程连接继续跑
- **拔电自动恢复**：使用电池时恢复系统默认睡眠，不会偷偷耗电
- **一键控制与卸载**：菜单栏开关、诊断、一键卸载后台助手

## 系统要求

- macOS 13 Ventura 或更新版本
- Apple Silicon 或 Intel Mac
- 首次启用需要管理员账号（安装后台助手，只需一次）

## 安装

### 方式一：GitHub Releases

1. 从 [Releases](https://github.com/pandengyao/PowerLock/releases) 下载 `PowerLock-1.0.0.dmg`（或 `.zip`）
2. 打开 dmg，把 `PowerLock.app` 拖进「应用程序」
3. 首次打开如果系统提示无法验证开发者：
   - 打开「系统设置 → 隐私与安全性」
   - 在「安全性」区域点「仍要打开」
   - 再打开一次 PowerLock
4. 首次启动会显示引导窗口，点「安装后台助手并启用」，输入一次管理员密码

### 方式二：Homebrew

```bash
brew install --cask pandengyao/tap/powerlock
```

（需要先安装 Homebrew；也可以直接下载 dmg。）

### 方式三：源码构建

只需要 Xcode Command Line Tools，不需要完整 Xcode：

```bash
xcode-select --install
git clone https://github.com/pandengyao/PowerLock.git
cd PowerLock
./scripts/build.sh
open build/PowerLock.app
```

图标已经提交在仓库里，构建不依赖 Python/Pillow。

## 使用

启动后菜单栏会出现一个锁形图标：

- **开锁图标**：已开启且正在插电工作
- **上锁图标**：已关闭
- **带斜杠的锁**：后台助手未安装

点击图标可以：

- 查看当前电源、屏幕保护程序、合盖运行状态
- 开启/关闭「插电不锁屏」
- 开启/关闭「合盖后保持运行」
- 设置登录时自动启动
- 打开系统「锁定屏幕」设置
- 查看诊断信息
- 一键卸载后台助手

## 工作原理

macOS 的「需要密码」是全局策略，普通 App 无法直接修改。PowerLock 的做法是：

1. 插电时把「屏幕保护程序」设为不自动启动，并让 AC 下显示器不休眠，屏幕保持常亮，自然不会触发锁屏
2. 插电且开启合盖模式时，通过后台助手执行 `pmset -a disablesleep 1`
3. 拔电或关闭功能时，助手恢复 `disablesleep 0` 和原来的 AC 显示器休眠时间

后台助手是一个随 App 内置、由 App 安装的 launchd 服务（`com.powerlock.helper`），安装时需要一次管理员授权：

- App 本体只以你的用户权限运行
- 助手以 root 运行，但只执行固定的 `pmset` 命令，不联网、不读取文件内容
- 卸载时由 App 停止、删除并恢复所有系统设置

电源变化通过 IOKit 通知监听，插拔瞬间响应，不做轮询。

## 卸载

推荐流程：

1. 菜单栏 PowerLock → **卸载后台助手…**
2. 确认后 App 会停止并删除助手、恢复系统睡眠设置、退出
3. 把 `PowerLock.app` 从「应用程序」移到废纸篓

如果 App 已经删除，可以手动清理：

```bash
sudo launchctl bootout system/com.powerlock.helper 2>/dev/null
sudo rm -f /Library/LaunchDaemons/com.powerlock.helper.plist \
           /Library/PrivilegedHelperTools/com.powerlock.helper
sudo pmset -a disablesleep 0
rm -f ~/Library/LaunchAgents/com.powerlock.login.plist
rm -rf ~/Library/Application\ Support/PowerLock
```

## 常见问题

**为什么需要管理员密码？**
合盖/睡眠开关（`pmset disablesleep`）只有 root 能改。PowerLock 用一个很小的后台助手完成这件事，安装时授权一次，之后不再打扰。

**为什么插电时屏幕一直亮着？**
因为系统「需要密码」是全局设置，显示器一旦休眠就会锁屏。要保持不锁屏，只能让屏幕保持常亮。如果希望「熄屏但不锁」，需要修改全局密码策略，PowerLock 当前不这样做。

**拔电后会不会一直耗电？**
不会。助手检测到电池供电会在几秒内恢复 `disablesleep 0`，屏幕保护程序和 AC 显示器休眠时间也会恢复。

**合盖后真的能继续运行吗？**
插电且开启「合盖后保持运行」时可以；电池供电时合盖仍会正常睡眠。

**为什么没有系统通知横幅？**
本地构建的 App 没有开发者签名，macOS 通知中心不允许其发送通知。PowerLock 不依赖通知，所有状态都在菜单栏和诊断窗口里。

**支持 Intel Mac 吗？**
发布包是 universal binary（arm64 + x86_64），最低 macOS 13。

**会收集数据吗？**
不会。没有网络请求、没有分析、没有上传；配置只保存在本机。

## 开发

```bash
./scripts/build.sh            # 构建到 build/PowerLock.app
UNIVERSAL=1 ./scripts/build.sh # universal 构建
./scripts/check.sh            # 语法/plist/构建/CLI 冒烟检查
./Tests/helper-test.sh        # 用 mock pmset 测试助手状态机
./scripts/verify.sh           # 安装后验收（助手、pmset、屏保、登录项）
VERSION=1.0.0 ./scripts/package.sh  # zip + dmg + SHA256
```

目录结构：

```
Sources/           App 源码（Swift）
Resources/         Info.plist、图标、后台助手与安装脚本
scripts/           构建、打包、检查、图标生成
Tests/             助手逻辑冒烟测试
docs/              Homebrew 模板、图片
.github/workflows/ CI
```

发布：打 tag（如 `v1.0.0`）后，GitHub Actions 会构建 universal 包并附到 Release。

## English

PowerLock is a tiny macOS menu bar utility that keeps your Mac awake and unlocked while plugged in, and restores normal sleep behavior on battery. It installs a small privileged helper once (admin approval) to toggle the system sleep flags; the app itself stays user-level. Requires macOS 13+, universal binary. Build with `./scripts/build.sh` (Xcode Command Line Tools only).

## License

[MIT](LICENSE)
