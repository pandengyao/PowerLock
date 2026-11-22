# PowerLock 开发与发布计划

> **实现状态（2026-11-22）**：M0–M6 已完成代码、构建、打包、文档与 CI；本机已安装 v1.0.0 并启动引导窗口。剩余需要用户交互的步骤：在引导窗口点「安装后台助手并启用」完成一次管理员授权（root 助手无法在无授权情况下安装）。公证/签名按计划留到后续版本。


> 目标：把当前「本机原型」重构成可通过 GitHub 免费分发、可长期维护的 macOS 菜单栏工具。
> 范围：v1.0.0 开源发布（GitHub Releases + Homebrew + 源码构建），暂不做公证/App Store。

---

## 1. 项目目标

**一句话**：插电时自动保持屏幕不锁、合盖继续运行；拔电自动恢复系统默认，全程菜单栏一键控制。

**v1 成功标准**

- 干净 Mac（默认设置：显示器 10 分钟休眠、需要密码「立即」）上安装后，插电不锁屏、合盖继续运行
- 拔电 5 秒内自动恢复睡眠，不残留 `SleepDisabled=1`
- 用户只需安装一个 `PowerLock.app`；后台助手由 App 安装/卸载
- 卸载后无残留（App、LaunchAgent、LaunchDaemon、配置、`pmset` 状态）
- GitHub 发布 ad-hoc 签名 universal 包，附 SHA256；Homebrew Cask 可安装
- 源码可用 Xcode CLT + `./build.sh` 一条命令构建

**v1 不做**

- App Store（沙盒与 root 助手冲突）
- 公证（免费阶段不做，后续视用户量再定）
- 多用户同时使用（v1 只跟随当前控制台用户）
- 自动更新（先手动下载；v1.1 再评估 Sparkle）
- 通知横幅（ad-hoc 签名拿不到通知权限，v1 不依赖通知）

---

## 2. 现状与差距

| 项目 | 现状 | 目标 |
|---|---|---|
| 代码结构 | 单文件 427 行、全局函数 | 拆分模块，可测试 |
| 后台 | 用户级 LaunchAgent 脚本 + 运行时 AppleScript 授权 | App 内置 root 助手，安装时授权一次 |
| 路径 | 写死 `/Users/frank`、`local.powerlock` | 动态路径、独立 bundle id |
| 屏幕保护 | 只改 `idleTime`，未管 `displaysleep` | 同时管 `displaysleep`（AC）与 `idleTime` |
| 合盖 | 全局 `disablesleep`，电池也生效 | 助手按电源自动切换，仅 AC 生效 |
| 登录启动 | 无 | 登录项/LaunchAgent，默认开启 |
| 卸载 | 手动命令 | App 内一键卸载，恢复所有状态 |
| 分发 | ad-hoc、仅本机 | GitHub Release + Homebrew + 源码构建 |
| 测试 | 无 | 测试矩阵 + 干净机器验收 |
| 文档 | 无 | README（中/英）、SECURITY、CHANGELOG |

---

## 3. v1 功能范围

### 3.1 插电不锁屏

- 插电且开启时：屏幕保护程序不自动启动（`idleTime=0`）、AC 下显示器不休眠（`pmset -c displaysleep 0`）
- 拔电或关闭时：恢复用户原来的屏幕保护时间与 AC 显示器休眠时间
- 说明：由于系统「需要密码」是全局策略，v1 采用「保持屏幕常亮」实现不锁屏；README 说明取舍

### 3.2 合盖后保持运行

- 插电且开启时：`pmset -a disablesleep 1`
- 拔电时：助手自动 `pmset -a disablesleep 0`（5 秒内）
- 关闭功能/卸载时：恢复 `0`
- 说明：该标志是系统级，必须由助手按电源状态切换，否则电池会持续耗电

### 3.3 菜单栏

- 状态：插电不锁屏（已开启/已关闭）、当前电源、屏保状态、合盖保持运行（已开启/已关闭/仅插电生效）
- 操作：两个开关、打开锁屏设置、诊断、卸载、退出
- 图标状态：正常 / 暂停（电池）/ 助手未安装 / 需要授权

### 3.4 安装与生命周期

- 首次启动引导：说明功能、权限、管理员要求、登录项
- 安装助手：一次管理员授权，写入 `/Library/LaunchDaemons`、`/Library/PrivilegedHelperTools`
- 登录时自动启动 App
- 卸载：停止并删除助手、LaunchAgent、配置、恢复 `pmset` 与屏幕保护设置

---

## 4. 目标架构

### 4.1 组件

```
PowerLock.app（用户级，LSUIElement）
├── MenuBarController        菜单与图标
├── PowerMonitor             IOKit 电源通知（AC/电池）
├── SettingsStore            UserDefaults + CFPreferences（屏幕保护）
├── HelperClient             写配置、读状态、安装/卸载
├── LoginItemManager         登录项（LaunchAgent 兜底）
├── OnboardingWindow         首次引导
└── Diagnostics              日志/状态导出

/Library/LaunchDaemons/com.<org>.powerlock.helper.plist   （root，随 App 安装）
/Library/PrivilegedHelperTools/com.<org>.powerlock.helper  （root 所有，固定逻辑）
```

> **交付物是一个 App，运行时是两个进程。**
> 菜单栏 App 以用户身份运行；改 `pmset` 必须以 root 运行，macOS 不允许把 GUI 进程直接提权成 root，也不建议让整个 App 以 root 运行。
> 助手文件全部位于 `PowerLock.app/Contents/...`，由 App 首次安装时复制到系统并注册；用户只下载/安装一个 App，助手没有图标、没有界面、不单独分发。
> 可选优化：同一个可执行文件支持 `--helper` 模式，App 安装时复制到 `/Library/PrivilegedHelperTools/`，代码只有一份。

### 4.2 职责划分

| 功能 | 执行者 | 权限 |
|---|---|---|
| 屏幕保护 `idleTime` | App | 用户 |
| AC 显示器休眠 `displaysleep` | 助手 | root |
| 合盖 `disablesleep` | 助手 | root |
| 电源状态 | App + 助手（IOKit） | - |
| 开关配置 | App 写文件，助手读取 | 用户写 / root 读 |

### 4.3 助手设计

- 独立可执行文件（v1 用 shell 实现：固定逻辑、不拼接用户输入、易审计；root 所有、755）
- 每 5 秒检查：控制台用户、电源状态、配置
- 只在状态变化时执行 `pmset`，避免频繁写
- 启动时自检：电池状态强制 `disablesleep 0`
- 退出/卸载时 `trap` 恢复：`disablesleep 0`、恢复 AC `displaysleep`
- 日志走 `os_log`（subsystem `com.<org>.powerlock.helper`）
- 配置文件：`~/Library/Application Support/PowerLock/config.plist`（仅布尔值，助手严格校验）
- 已知限制：配置为用户可写，任何用户进程都能切换开关；影响仅限睡眠，README/安全说明中写明

### 4.4 安装方式（免费/未签名阶段）

- App 内置助手文件与 plist
- 首次开启时通过一次管理员授权执行安装脚本（`osascript with administrator privileges` 或 Authorization Services）
- 安装脚本：校验路径、复制文件、设置权限、`launchctl bootstrap system`、`launchctl enable`
- 卸载：`launchctl bootout system`、删除文件、恢复 `pmset`
- 后续拿到签名后可迁移到 `SMAppService.daemon`，对用户无感

---

## 5. 里程碑与时间表

按**兼职（每周 10–15 小时）8 周**估算；全职可压缩到 5 周。

| 里程碑 | 周 | 交付物 | 验收 |
|---|---|---|---|
| M0 立项 | W1 | 仓库骨架、LICENSE、README 初稿、CI 空跑 | `git clone` 后能构建 |
| M1 重构 | W2 | App 模块拆分、PowerMonitor（IOKit）、SettingsStore | 无功能回归，代码可读 |
| M2 助手 | W3 | helper 二进制/脚本、安装/卸载、配置协议、失效保护 | 手动安装/卸载后 `pmset` 状态正确 |
| M3 核心逻辑 | W4 | 插电/电池状态机、`displaysleep`、`idleTime`、合盖切换、登录项 | 干净用户下插拔各 20 次无残留 |
| M4 交互 | W5 | 首次引导、菜单状态、诊断、卸载入口、中英文本 | 新用户 3 分钟内完成安装 |
| M5 发布工程 | W6 | universal 构建、ad-hoc 签名、dmg/zip、SHA256、GitHub Release 工作流、Homebrew Cask | 干净 Mac 下载安装成功 |
| M6 Beta | W7 | 预发布、测试矩阵、修复 | 测试矩阵全绿 |
| M7 v1.0 | W8 | 正式 Release、README/截图/GIF、宣传材料 | 发布检查清单全部通过 |

缓冲：每个里程碑预留 1–2 天；W7 集中处理 Gatekeeper/干净机器问题。

---

## 6. 详细任务清单

### 6.1 工程重构（M1）

- [ ] 建立 Xcode 工程或 SPM 结构（保留 `build.sh` 用 `swiftc`）
- [ ] 拆分：`PowerMonitor`、`SettingsStore`、`HelperClient`、`LoginItemManager`、`MenuBarController`、`OnboardingWindow`
- [ ] 移除全局可变状态与 427 行单文件
- [ ] 用 `CFPreferences` 读写 `com.apple.screensaver`（替换 `defaults` 子进程）
- [ ] 用 `IOPSNotificationCreateRunLoopSource` 监听电源（替换 3 秒轮询）
- [ ] 统一错误模型与 `os_log`，移除自写日志文件
- [ ] bundle id 改为 `com.<org>.powerlock`，版本号从构建参数注入

### 6.2 核心逻辑（M3）

- [ ] AC/电池状态机：开启、暂停、恢复、失败回滚
- [ ] `displaysleep` 记忆与恢复（AC 专用）
- [ ] `disablesleep` 仅在 AC 为 1，电池必为 0
- [ ] 屏幕保护 `idleTime` 记忆/恢复（复用 `lastDelayTime` 逻辑）
- [ ] 合盖/开盖、睡眠/唤醒、注销/登录、快速用户切换
- [ ] 助手崩溃/被杀/卸载后的状态恢复
- [ ] 电池电量低、外接显示器、合盖启动等边界
- [ ] 标准用户（非管理员）提示与降级

### 6.3 助手（M2）

- [ ] 实现 helper（固定逻辑，不拼接用户输入）
- [ ] 安装器：校验、复制、权限、`launchctl bootstrap system`
- [ ] 卸载器：`bootout`、删除、恢复 `pmset`
- [ ] 自检：启动时若电池则 `disablesleep 0`
- [ ] 配置读取：控制台用户 + 严格布尔校验
- [ ] 日志与状态文件（可选）
- [ ] 版本化：App 升级时助手同步升级

### 6.4 交互（M4）

- [ ] 首次引导窗口（功能、权限、管理员、登录项、隐私）
- [ ] 菜单状态完整（已开启/已暂停/助手缺失/需授权）
- [ ] 图标状态与无障碍描述
- [ ] 一键卸载（含恢复状态）
- [ ] 诊断：复制版本、电源、`pmset`、助手状态
- [ ] 中英文本（String Catalog）
- [ ] 无通知依赖；不弹模态提醒

### 6.5 发布工程（M5）

- [ ] `build.sh` 只依赖 Xcode CLT；图标 `.icns` 入库（去掉 Pillow 依赖）
- [ ] universal 构建（arm64 + x86_64）
- [ ] ad-hoc 签名（App + helper），`codesign --verify`
- [ ] 生成 dmg/zip + SHA256
- [ ] GitHub Actions：tag 触发构建、测试、上传 Release
- [ ] Homebrew Tap + Cask（url/sha256/app/zap）
- [ ] README：安装、首次打开（中性措辞）、卸载、FAQ
- [ ] 截图 + 15 秒 GIF/视频
- [ ] `SECURITY.md`（助手做什么、如何验证/删除）
- [ ] `CHANGELOG.md`、`CONTRIBUTING.md`、Issue 模板

### 6.6 文档（M7）

- [ ] README 中文（主）+ 英文
- [ ] 安装/卸载/首次打开图文
- [ ] 常见问题：管理员密码、Gatekeeper、电池行为、屏幕常亮说明
- [ ] 架构说明（helper 权限模型）
- [ ] 兼容性矩阵

---

## 7. 测试矩阵

| 维度 | 用例 |
|---|---|
| 系统 | macOS 13 / 14 / 15 / 26（有 27 更好） |
| 芯片 | Apple Silicon 必测；Intel 至少 CI 构建 + 一次实机/VM |
| 账号 | 管理员、标准用户、干净用户（默认 prefs） |
| 电源 | 插电、拔电、反复插拔 20 次、电池低电量 |
| 盖子 | 开盖/合盖/合盖启动/外接显示器 |
| 会话 | 登录/注销/重启/快速用户切换 |
| 安装 | 首次安装、升级、卸载、残留检查 |
| 分发 | Safari 下载（quarantine）、curl/gh 下载、Homebrew 安装 |
| 异常 | 助手被杀、App 强退、安装中断、断电 |

**关键验收**：干净用户默认设置（显示器 10 分钟休眠、密码立即）下，安装后插电确实不锁屏；拔电 5 秒内恢复睡眠；卸载后 `pmset -g` 无 `SleepDisabled 1`。

---

## 8. 发布检查清单

- [ ] 版本号/构建号更新，CHANGELOG 写好
- [ ] 干净 Mac 全流程：下载 → 首次打开放行 → 安装助手 → 插拔 → 合盖 → 卸载
- [ ] universal 检查：`lipo -info` 包含 arm64/x86_64
- [ ] `codesign --verify --deep --strict` 通过
- [ ] dmg/zip + SHA256 上传
- [ ] GitHub Release Notes（功能、安装、已知问题）
- [ ] Homebrew Cask `brew audit --cask` 通过
- [ ] README 截图/GIF 更新
- [ ] SECURITY/隐私说明
- [ ] 社交媒体文案与配图
- [ ] 发布后 24 小时盯 Issue

---

## 9. 风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| 未公证被 Gatekeeper 拦 | 首次安装流失 | README 图文 + GIF；Homebrew 路径；后续公证 |
| 用户不信任 root 助手 | 不敢装 | 开源、固定逻辑、SECURITY.md、一键卸载 |
| macOS 改私有偏好 | 功能失效 | 版本矩阵测试；功能探测；降级提示 |
| 助手残留 `SleepDisabled=1` | 电池耗电 | 启动自检、退出 trap、卸载恢复、测试用例 |
| 多用户冲突 | 状态错乱 | v1 只跟随控制台用户，文档说明 |
| Intel 兼容 | 部分用户打不开 | CI 构建 universal；至少一次实机验证 |
| 屏幕常亮耗电/烧屏 | 用户抱怨 | 文案说明；v1.1 评估「允许熄屏但不锁」模式 |
| 名称/商标冲突 | 被迫改名 | 发布前查 GitHub/App Store/商标 |
| 苹果开发者账号成本 | 无法公证 | 免费分发三件套；有用户量后再投入 |

---

## 10. 运营与推广（发布周）

- GitHub：README 首屏 GIF、功能三点、安装一条命令、FAQ
- 小红书：3 条内容（痛点演示 15 秒视频、安装教程、合盖运行场景），评论区引导 GitHub
- 知乎：一篇技术文章（macOS 锁屏/睡眠机制、为什么需要助手、免费分发说明）
- 宣传材料只写功能、安装步骤与使用场景
- 收集 Issue 标签：`bug`、`enhancement`、`question`、`docs`

---

## 11. 预算

| 项目 | 费用 |
|---|---|
| GitHub（公开仓库/Actions） | 0 |
| Homebrew Tap | 0 |
| 域名（可选） | ~¥60/年 |
| Apple Developer（公证，可选） | $99/年，v1 不做 |
| 图标/截图 | 0（自制） |

---

## 12. 后续路线（v1.1+）

- 自动更新（Sparkle，EdDSA 签名免费）
- 「允许熄屏但不锁定」高级模式（需改全局密码策略，强提示）
- 多用户支持
- 公证 + 签名（有预算后）
- Intel 实机兼容性验证
- 菜单栏图标自定义、快捷键
- 本地化扩展（英/日）

---

## 13. 当前下一步（本周）

1. 建 GitHub 仓库（私有开发，发布时转公开）
2. 跑通 `build.sh` 无 Python 依赖
3. 拆分 `PowerMonitor` + `SettingsStore`，替换 3 秒轮询
4. 设计助手配置协议与安装/卸载脚本
5. 搭 GitHub Actions 骨架（构建 + 产物）
