# 发布检查清单

发布前逐项确认。

## 1. 替换占位符

- [ ] `README.md` 中的 `OWNER` 换成实际 GitHub 用户名/组织
- [ ] `docs/homebrew/powerlock.rb` 中的 `OWNER`、`sha256`
- [ ] `Resources/Info.plist` 的 `CFBundleIdentifier`（默认 `com.powerlock.app`，建议换成自己的反写域名）
- [ ] `Sources/Core.swift`、`Resources/Helper/*.plist`、`install-helper.sh`、`uninstall-helper.sh` 中的 `com.powerlock.*` 标识（如果改了 bundle id）
- [ ] `LICENSE` 的版权人

> 标识一旦发布就不要再改，否则旧版助手无法被新版覆盖。

## 2. 版本与变更

- [ ] `CHANGELOG.md` 写好
- [ ] `VERSION` / `BUILD` 确认
- [ ] README 截图/GIF（菜单、引导窗口）

## 3. 构建与产物

```bash
./scripts/check.sh
./Tests/helper-test.sh
VERSION=1.0.0 UNIVERSAL=1 ./scripts/package.sh
lipo -info build/PowerLock.app/Contents/MacOS/PowerLock   # x86_64 + arm64
codesign --verify --deep --strict build/PowerLock.app
cat build/dist/SHA256SUMS.txt
```

- [ ] `codesign --verify` 通过（ad-hoc 签名）
- [ ] zip / dmg / SHA256 都在 `build/dist`
- [ ] Intel slice 可运行（Rosetta：`arch -x86_64 ... --status`）

## 4. 干净机器验收

在**全新用户**（默认设置：显示器 10 分钟休眠、需要密码「立即」）上：

- [ ] 浏览器下载 dmg，首次打开出现 Gatekeeper 提示
- [ ] 按 README 步骤「隐私与安全性 → 仍要打开」后能启动
- [ ] 引导窗口出现，安装助手时弹出一次管理员授权
- [ ] 插电：屏幕不自动锁、合盖后继续运行
- [ ] 拔电：5 秒内恢复睡眠（`pmset -g` 无 `SleepDisabled 1`）
- [ ] 菜单开关、登录项、诊断都正常
- [ ] 菜单「卸载后台助手…」后无残留：

```bash
sudo launchctl print system/com.powerlock.helper   # 应不存在
ls /Library/LaunchDaemons/com.powerlock.helper.plist          # 应不存在
ls /Library/PrivilegedHelperTools/com.powerlock.helper        # 应不存在
pmset -g | grep SleepDisabled                                 # 应为空或 0
```

## 5. 发布

- [ ] 提交并打 tag：`git tag v1.0.0 && git push --tags`
- [ ] GitHub Actions 的 release 工作流成功
- [ ] Release 附件包含 zip、dmg、SHA256SUMS.txt
- [ ] Release Notes 说明安装步骤与首次打开处理
- [ ] 更新 Homebrew tap 的 cask（url + sha256）
- [ ] 发布后 24 小时盯 Issue

## 6. 宣传

- [ ] 小红书：15 秒演示视频（插电合盖继续跑 + 拔电恢复）、安装教程
- [ ] 知乎：技术文章（macOS 锁屏/睡眠机制、为什么需要助手）
- [ ] README 首屏 GIF
