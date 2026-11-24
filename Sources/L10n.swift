import Foundation

/// 界面文案。系统首选语言是中文时用中文，其他语言用英文。
///
/// 构建只用 swiftc，不走 Xcode，所以没有用 .strings / String Catalog：
/// 文案集中在这一个文件里，中英对照，加新文案时两种语言一起写。
enum L {
    /// POWERLOCK_LANG=en / zh 可以强制语言，用于预览截图。
    /// 和系统按 Info.plist 的 CFBundleLocalizations 选出的语言保持一致，这样 PowerLock 的文案和
    /// AppKit 自带的文案（右键菜单、系统提示）是同一种语言。繁体中文目前也显示英文。
    static var isChinese: Bool = {
        if let forced = ProcessInfo.processInfo.environment["POWERLOCK_LANG"] {
            return forced.hasPrefix("zh")
        }
        let chosen = Bundle.preferredLocalizations(from: ["en", "zh-Hans"],
                                                   forPreferences: Locale.preferredLanguages).first
        return chosen == "zh-Hans"
    }()

    private static func t(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }

    // MARK: 状态

    static var headerActive: String { t("正在保持在线", "Keeping your Mac awake") }
    static var headerPaused: String { t("已暂停：正在用电池", "Paused: on battery") }
    static var headerOff: String { t("已关闭", "Off") }
    static var headerNoHelper: String { t("还没完成设置", "Setup needed") }
    static var headerHelperOutdated: String { t("后台助手需要更新", "Helper needs an update") }

    static var detailActiveBoth: String { t("屏幕不会自动锁定，合盖后继续运行", "Screen won't auto-lock. Keeps running with the lid closed.") }
    static var detailActiveNoLock: String { t("屏幕不会自动锁定", "Screen won't auto-lock.") }
    static var detailActiveLid: String { t("合盖后继续运行，屏幕按系统设置锁定", "Keeps running with the lid closed. Screen locks as usual.") }
    static var detailActiveNone: String { t("两个功能都关着，相当于没开启", "Both options are off, so nothing is changed.") }
    static var detailPaused: String { t("插上电源后自动恢复，合盖会正常睡眠", "Resumes when you plug in. Closing the lid sleeps as usual.") }
    static var detailOff: String { t("系统按默认设置睡眠和锁屏", "Your Mac sleeps and locks as usual.") }
    static var detailNoHelper: String { t("需要安装后台助手才能生效", "Install the helper to start.") }
    static var detailHelperOutdated: String { t("更新后才能用上新功能和修复", "Update it to get new features and fixes.") }

    // MARK: 菜单

    /// 带勾选的开关：用状态名，不用动词，避免勾选后读成「开启」这个动作。
    static var turnOn: String { t("启用 PowerLock", "PowerLock Enabled") }
    static var optionsSection: String { t("插电时", "While plugged in") }
    static var optionNoLock: String { t("不自动锁屏", "Don't auto-lock the screen") }
    static var optionLid: String { t("合盖后继续运行", "Keep running with the lid closed") }
    static var optionNoLockHint: String { t("屏幕保持常亮", "Keeps the display on") }
    static var optionLidHint: String { t("用电池时合盖照常睡眠，除非打开下面的「用电池时也合盖运行」", "On battery, closing the lid still sleeps unless you turn on the On battery option below") }

    // MARK: 用电池时合盖运行

    static var batterySection: String { t("用电池时", "On battery") }
    static var batteryLid: String { t("也合盖运行", "Also keep running with the lid closed") }
    static var batteryLidHint: String { t("电量低、开了低电量模式或到了定时时间会自动停止", "Stops automatically at low battery, in Low Power Mode, or when the timer ends") }
    static var batteryFloorMenu: String { t("电量低于多少时停止", "Stop below") }
    static func batteryFloorItem(_ pct: Int) -> String { "\(pct)%" }
    static var batteryTimerMenu: String { t("定时停止", "Timer") }
    static var batteryTimerNone: String { t("不限时", "No time limit") }
    static func batteryTimerItem(_ hours: Int) -> String { t("\(hours) 小时后", hours == 1 ? "Stop after 1 hour" : "Stop after \(hours) hours") }
    static func batteryTimerActive(_ remaining: String) -> String { t("还剩 \(remaining)", "\(remaining) left") }
    static func durationText(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return t("\(h) 小时 \(m) 分", "\(h)h \(m)m") }
        if h > 0 { return t("\(h) 小时", "\(h)h") }
        return t("\(m) 分钟", "\(m)m")
    }

    static var batteryConfirmTitle: String { t("用电池时也合盖运行？", "Keep running lid-closed on battery?") }
    static func batteryConfirmBody(floor: Int) -> String {
        t("打开后，用电池时 Mac 不会自动睡眠，开着盖也一样，只有显示器照常关闭。合上盖子后散热比开盖差，长时间满负载会明显发热；电量也会持续消耗。\n\nPowerLock 会在这些情况下自动停止，让 Mac 正常睡眠：\n· 电量低于 \(floor)%\n· 打开了低电量模式\n· 读不到电量\n· 到了定时时间（默认不限时，打开后可以在菜单里设 1、2、4 小时）\n\n电量下限和定时可以在菜单里改。",
          "On battery, your Mac won't sleep on its own, even with the lid open. Only the display turns off. With the lid closed, the Mac cools less well and can get warm under sustained load, and the battery keeps draining.\n\nPowerLock stops automatically and lets the Mac sleep when:\n· battery drops below \(floor)%\n· Low Power Mode is on\n· the battery level can't be read\n· the timer runs out (no limit by default; set 1, 2 or 4 hours in the menu after turning this on)\n\nYou can change the battery floor and the timer in the menu.")
    }
    static var batteryConfirmButton: String { t("打开", "Turn On") }

    static var headerBatteryActive: String { t("正在用电池保持在线", "Awake on battery") }
    static func detailBatteryActive(floor: Int, timer: String?) -> String {
        // 有定时时去掉「合盖继续运行」，标题已经说了在线，这样一行放得下
        guard let timer else {
            return t("合盖继续运行，电量低于 \(floor)% 自动停止", "Keeps running lid-closed, stops below \(floor)%")
        }
        return t("电量低于 \(floor)% 自动停止，\(timer)", "Stops below \(floor)%, \(timer)")
    }
    static func detailBatteryStoppedLow(floor: Int) -> String {
        t("电量低于 \(floor)%，已恢复正常睡眠。插上电源后自动恢复", "Below \(floor)%, so normal sleep is back. Resumes when you plug in.")
    }
    static var detailBatteryStoppedLPM: String {
        t("低电量模式已打开，已恢复正常睡眠", "Low Power Mode is on, so normal sleep is back.")
    }
    static var detailBatteryStoppedUnreadable: String {
        t("读不到电池电量，已恢复正常睡眠", "Can't read the battery level, so normal sleep is back.")
    }
    static var tooltipBatteryActive: String { t("PowerLock：用电池保持在线", "PowerLock: awake on battery") }
    static var launchAtLogin: String { t("登录时启动", "Launch at Login") }
    static var installHelper: String { t("完成设置…", "Finish Setup…") }
    static var updateHelper: String { t("更新后台助手…", "Update Helper…") }
    static var more: String { t("更多", "More") }
    static var lockScreenSettings: String { t("系统「锁定屏幕」设置…", "Lock Screen Settings…") }
    static var diagnostics: String { t("诊断信息…", "Diagnostics…") }
    static var checkForUpdates: String { t("检查更新…", "Check for Updates…") }
    static var reportIssue: String { t("反馈问题…", "Report an Issue…") }
    static var aboutItem: String { t("关于 PowerLock", "About PowerLock") }
    static var uninstall: String { t("卸载 PowerLock…", "Uninstall PowerLock…") }
    static var quit: String { t("退出 PowerLock", "Quit PowerLock") }

    static var tooltipActive: String { t("PowerLock：正在保持在线", "PowerLock: keeping your Mac awake") }
    static var tooltipPaused: String { t("PowerLock：已暂停（电池）", "PowerLock: paused on battery") }
    static var tooltipOff: String { t("PowerLock：已关闭", "PowerLock: off") }
    static var tooltipAttention: String { t("PowerLock：需要设置", "PowerLock: setup needed") }
    static var tooltipHelperOutdated: String { t("PowerLock：后台助手需要更新", "PowerLock: helper needs an update") }

    // MARK: 首次引导

    static var onboardingTitle: String { t("插着电，Mac 就一直在线", "Stay awake while plugged in") }
    static var onboardingSubtitle: String {
        t("拔掉电源，一切自动恢复。不用记着开关。",
          "Unplug and everything goes back to normal. Nothing to remember.")
    }
    static var featureNoLockTitle: String { t("插电时不自动锁屏", "No auto-lock while plugged in") }
    static var featureNoLockBody: String { t("回到电脑前不用再输密码。屏幕会保持常亮。", "No password every time you come back. The display stays on.") }
    static var featureLidTitle: String { t("合盖继续运行", "Runs with the lid closed") }
    static var featureLidBody: String { t("AI 编程助手、编译、下载合上盖子也照常跑，不用外接显示器。", "Agents, builds and downloads keep going. No external display needed.") }
    static var featureBatteryTitle: String { t("拔电自动恢复", "Back to normal on battery") }
    static var featureBatteryBody: String { t("用电池时按系统设置睡眠；合着盖拔电会立即睡眠。", "Normal sleep on battery. Unplug with the lid closed and it sleeps right away.") }
    static var onboardingPrivacy: String {
        t("需要输入一次管理员密码，安装一个只修改睡眠设置的后台助手。不联网，不收集任何数据。",
          "You'll enter your admin password once to install a small helper that only changes sleep settings. No network access, no data collected.")
    }
    static var onboardingLaunchAtLogin: String { t("登录时启动 PowerLock", "Launch PowerLock at login") }
    static var onboardingEnable: String { t("安装并开启", "Install and Turn On") }
    static var onboardingLater: String { t("以后再说", "Not Now") }
    static var onboardingInstalling: String { t("正在安装…", "Installing…") }
    static var onboardingCancelled: String { t("已取消。准备好以后再点一次就行。", "Cancelled. Click again when you're ready.") }
    static var onboardingDoneTitle: String { t("设置完成", "You're all set") }
    static var onboardingDoneBody: String {
        t("PowerLock 在菜单栏右上角。插着电时图标上有闪电，表示正在生效。",
          "PowerLock lives in the menu bar. A bolt on the lock means it's working.")
    }
    static var onboardingDoneButton: String { t("好", "Done") }

    // MARK: 提示框

    static var ok: String { t("好", "OK") }
    static var cancel: String { t("取消", "Cancel") }
    static var later: String { t("稍后", "Later") }

    static var updateHelperTitle: String { t("需要更新后台助手", "Update the helper") }
    static var updateHelperBody: String {
        t("这个版本的 PowerLock 带有更新过的后台助手，新功能和修复要更新后才生效。更新需要输入一次管理员密码。",
          "This version of PowerLock comes with an updated helper. New features and fixes take effect after you update it. You'll need to enter your admin password once.")
    }
    static var updateNow: String { t("现在更新", "Update Now") }
    static var helperUpdatedTitle: String { t("后台助手已更新", "Helper updated") }
    static var installFailedTitle: String { t("安装失败", "Couldn't install the helper") }
    static var updateFailedTitle: String { t("更新失败", "Couldn't update the helper") }

    static var checkUpdateFailedTitle: String { t("无法检查更新", "Couldn't check for updates") }
    static var checkUpdateFailedBody: String { t("连不上 GitHub，请稍后再试。", "Couldn't reach GitHub. Try again later.") }
    static func newVersionTitle(_ v: String) -> String { t("PowerLock \(v) 已发布", "PowerLock \(v) is available") }
    static func newVersionBody(current: String, brew: Bool) -> String {
        let base = t("你现在用的是 \(current)。", "You have \(current).")
        guard brew else { return base }
        return base + t("\n用 Homebrew 安装的，可以运行：brew upgrade --cask powerlock",
                        "\nInstalled with Homebrew? Run: brew upgrade --cask powerlock")
    }
    static var openReleasePage: String { t("查看新版本", "View Release") }
    static var copyBrewCommand: String { t("复制升级命令", "Copy Command") }
    static func upToDateTitle(_ v: String) -> String { t("已是最新版本", "PowerLock is up to date") }
    static func upToDateBody(_ v: String) -> String { t("当前版本 \(v)。", "You have version \(v).") }

    static var uninstallTitle: String { t("卸载 PowerLock？", "Uninstall PowerLock?") }
    static var uninstallBody: String {
        t("会删除后台助手、恢复系统的睡眠和锁屏设置，然后退出。之后把 PowerLock 从「应用程序」里删掉即可。",
          "This removes the helper, restores your sleep and lock settings, and quits. Then move PowerLock to the Trash.")
    }
    static var uninstallButton: String { t("卸载并退出", "Uninstall and Quit") }
    static var uninstallFailedTitle: String { t("卸载失败", "Couldn't uninstall") }

    static var authCancelled: String { t("已取消管理员授权。", "Admin authorization was cancelled.") }
    static var internalError: String { t("内部错误", "Internal error") }
    static var helperResourcesMissing: String { t("App 里找不到后台助手的文件，请重新下载 PowerLock。", "The helper files are missing from the app. Please download PowerLock again.") }
    static var authScriptFailed: String { t("无法请求管理员授权。", "Couldn't ask for admin authorization.") }
    static var unknownError: String { t("未知错误", "Unknown error") }

    // MARK: 演示动画（README 用）

    static var demoCaptionPlugged: String { t("插着电：不锁屏，合盖继续跑", "Plugged in: no lock, runs lid-closed") }
    static var demoCaptionUnplugged: String { t("拔掉电源：自动暂停，正常睡眠", "Unplugged: paused, sleeps as usual") }
    static var demoCaptionPluggedBack: String { t("插回电源：自动恢复", "Plugged back in: on again") }
    static var demoCaptionOff: String { t("随时可以关掉", "Turn it off any time") }

    // MARK: 关于

    static var aboutTagline: String {
        t("插电时不锁屏、合盖继续运行；拔电自动恢复。",
          "While plugged in, your Mac stays unlocked and keeps running with the lid closed. Back to normal on battery.")
    }
    static var aboutGitHub: String { t("GitHub", "GitHub") }
    static var aboutLicense: String { t("MIT 开源许可", "MIT License") }

    // MARK: 诊断

    static var diagnosticsTitle: String { t("PowerLock 诊断信息", "PowerLock Diagnostics") }
    static var diagnosticsHint: String {
        t("反馈问题时，请把下面的内容附在 Issue 里。",
          "When reporting an issue, please include the text below.")
    }
    static var copy: String { t("拷贝", "Copy") }
    static var copied: String { t("已拷贝", "Copied") }
    static var refresh: String { t("刷新", "Refresh") }
    static var openIssue: String { t("新建 Issue…", "New Issue…") }

    static var powerAC: String { t("电源适配器", "Power adapter") }
    static var powerBattery: String { t("电池", "Battery") }
}
