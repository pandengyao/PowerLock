# 发布检查清单

发布前逐项确认。

> 标识（`com.powerlock.*`）已经发布，不要再改，否则旧版助手无法被新版覆盖。

## 1. 版本与变更

- [ ] `Resources/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 已更新（构建脚本和 Release 工作流都以它为准，tag 必须与之一致）
- [ ] 助手逻辑有变化时，`Resources/Helper/powerlock-helper.sh` 里的 `HELPER_VERSION` 加 1
- [ ] `CHANGELOG.md` 写好，把"未发布"改成日期
- [ ] README 截图/GIF 是否需要更新。界面截图用 `build/PowerLock.app/Contents/MacOS/PowerLock --render-previews build/previews` 离屏生成（中英文 × 浅色/深色）；演示动画用 `POWERLOCK_LANG=zh … --render-demo docs/images/demo.gif` 和 `POWERLOCK_LANG=en … --render-demo docs/images/demo-en.gif`
- [ ] 系统语言分别设为中文和英文，各打开一次菜单和引导窗口

## 2. 构建与产物

```bash
./scripts/check.sh
./Tests/helper-test.sh
./scripts/package.sh
lipo -info build/PowerLock.app/Contents/MacOS/PowerLock   # x86_64 + arm64
codesign --verify --deep --strict build/PowerLock.app
cat build/dist/SHA256SUMS.txt
```

- [ ] `codesign --verify` 通过（ad-hoc 签名）
- [ ] zip / dmg / SHA256 都在 `build/dist`
- [ ] Intel slice 可运行（Rosetta：`arch -x86_64 build/PowerLock.app/Contents/MacOS/PowerLock --status`）

## 3. 真机验收

在默认设置的用户下（显示器 10 分钟休眠、需要密码「立即」）：

- [ ] 浏览器下载 dmg，首次打开出现 Gatekeeper 提示，按 README 放行后能启动
- [ ] 引导窗口出现，安装助手时弹出一次管理员授权
- [ ] 插电：屏幕不自动锁、合盖后继续运行（合盖后 SSH 进去或看下载进度）
- [ ] 开盖拔电（「用电池时也合盖运行」关闭，默认）：5 秒内 `pmset -g | grep SleepDisabled` 为 0
- [ ] **合盖拔电**（同上，选项关闭）：合盖插电运行 1 分钟后拔电，10 秒内 Mac 睡眠（`pmset -g log | grep -i "Entering Sleep"`）
- [ ] 合盖 + 外接显示器拔电：不睡眠（系统本身就不会因合盖睡眠）

「用电池时也合盖运行」打开时：

- [ ] 合盖插电运行 1 分钟后拔电，Mac 继续运行（SSH 进去或看下载进度），`SleepDisabled` 为 1
- [ ] 合盖运行时，从另一台电脑 SSH 进去把配置里的 `batteryFloor` 改成高于当前电量（`plutil -replace batteryFloor -integer 90 ~/Library/Application\ Support/PowerLock/config.plist`）：10 秒内 Mac 睡眠；之后在电池上合着盖不会自己醒来继续运行，开盖或插电后恢复
- [ ] 打开低电量模式：10 秒内恢复睡眠，菜单显示「低电量模式已打开」
- [ ] 设 1 小时定时：到期后恢复睡眠，菜单里的选项自动关掉
- [ ] 用电池合盖运行时执行 `sudo launchctl kickstart -k system/com.powerlock.helper`：新助手接着保持运行
- [ ] 用电池合盖运行时通过 SSH 执行 `sudo shutdown -r now`：正常重启，中途不会睡下去
- [ ] 从上一版本升级、助手还没更新时，「用电池时」下面的选项是灰的；更新助手后可用
- [ ] 从上一版本升级：如果助手有更新，菜单栏图标右上角出现圆点，弹窗更新助手后恢复正常
- [ ] 菜单开关、登录项、诊断都正常
- [ ] 菜单「更多 → 卸载 PowerLock…」后无残留：

```bash
sudo launchctl print system/com.powerlock.helper              # 应不存在
ls /Library/LaunchDaemons/com.powerlock.helper.plist          # 应不存在
ls /Library/PrivilegedHelperTools/com.powerlock.helper        # 应不存在
ls "/Library/Application Support/PowerLock"                   # 应不存在
pmset -g | grep SleepDisabled                                 # 应为 0
defaults -currentHost read com.apple.screensaver idleTime     # 应为原值或不存在
```

## 4. 发布

- [ ] 合并到 main，打 tag：`git tag v1.1.0 && git push origin v1.1.0`
- [ ] GitHub Actions 的 release 工作流成功
- [ ] Release 附件包含 zip、dmg、SHA256SUMS.txt
- [ ] `gh attestation verify PowerLock-<版本>.dmg -R pandengyao/PowerLock` 通过
- [ ] Release Notes 写明安装步骤、首次打开处理、本版本是否需要更新助手
- [ ] 更新 `pandengyao/homebrew-tap` 的 `Casks/powerlock.rb`（以 `docs/homebrew/powerlock.rb` 为模板，填 version 和 sha256），并在本仓库同步模板
- [ ] `brew update && brew upgrade --cask powerlock` 实测一次
- [ ] 发布后 24 小时内看 Issue
