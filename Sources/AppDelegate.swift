import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let store = ConfigStore()
    private let helper = HelperManager()
    private let login = LoginItemManager()
    private let power = PowerMonitor()
    private var refreshTimer: Timer?
    private var onboarding: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        _ = Legacy.migrateIfNeeded(into: store)
        Legacy.cleanup()
        if FileManager.default.fileExists(atPath: AppInfo.configPath) {
            store.update { $0.appRunning = true }
        }

        power.start()
        power.onChange { [weak self] in
            self?.applyScreenSaver()
            self?.refresh()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        applyScreenSaver()
        refresh()

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.applyScreenSaver()
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        if !helper.isInstalled {
            showOnboarding()
        } else if helper.needsUpdate {
            DispatchQueue.main.async { [weak self] in
                self?.promptHelperUpdate()
            }
        }
    }

    /// 「插电不锁屏」需要 App 在运行：退出时恢复屏幕保护，并通知助手恢复显示器休眠，
    /// 避免卸载或退出后留下「永不启动」。合盖运行由后台助手负责，不受 App 退出影响。
    func applicationWillTerminate(_ notification: Notification) {
        ScreenSaver.restore()
        if FileManager.default.fileExists(atPath: AppInfo.configPath) {
            store.update { $0.appRunning = false }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 状态与图标

    private var statusText: String {
        if !helper.isInstalled { return "后台助手未安装" }
        if helper.needsUpdate { return "后台助手需要更新" }
        if !store.config.enabled { return "已关闭" }
        return power.isOnAC ? "已开启（插电不锁屏）" : "已开启（电池中，已暂停）"
    }

    private func applyScreenSaver() {
        if store.config.enabled && store.config.noLock && power.isOnAC {
            ScreenSaver.disableAutoLock()
        } else {
            ScreenSaver.restore()
        }
    }

    private func refresh() {
        let symbol: String
        if !helper.isInstalled {
            symbol = "lock.slash"
        } else if helper.needsUpdate {
            symbol = "lock.trianglebadge.exclamationmark"
        } else if !store.config.enabled {
            symbol = "lock.fill"
        } else {
            symbol = power.isOnAC ? "lock.open.fill" : "lock.open"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PowerLock")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "PowerLock：\(statusText)"
    }

    // MARK: - 首次引导

    private func showOnboarding() {
        if let onboarding {
            onboarding.show()
            return
        }
        let window = OnboardingWindow(
            onEnable: { [weak self] wantsLogin in
                guard let self else { return (false, "内部错误") }
                let result = self.helper.install(bundlePath: Bundle.main.bundlePath)
                guard result.ok else {
                    return (false, result.cancelled ? "已取消管理员授权" : result.message)
                }
                self.store.update { $0.enabled = true }
                if wantsLogin { self.login.enable() }
                self.applyScreenSaver()
                self.refresh()
                return (true, "")
            },
            onFinish: { [weak self] _ in
                self?.onboarding = nil
            }
        )
        onboarding = window
        window.show()
    }

    // MARK: - 菜单

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let installed = helper.isInstalled

        addInfo(menu, "状态：\(statusText)")
        addInfo(menu, "当前电源：\(PowerMonitor.label())")
        addInfo(menu, "屏幕保护程序：\(idleText())")
        addInfo(menu, "合盖后保持运行：\(lidText())")

        menu.addItem(.separator())

        if installed && helper.needsUpdate {
            let update = NSMenuItem(title: "更新后台助手…", action: #selector(updateHelper), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }

        if installed {
            let noLock = NSMenuItem(
                title: store.config.noLock ? "关闭「插电不锁屏」" : "开启「插电不锁屏」",
                action: #selector(toggleNoLock),
                keyEquivalent: ""
            )
            noLock.target = self
            menu.addItem(noLock)

            let lid = NSMenuItem(
                title: store.config.lidAwake ? "关闭「合盖后保持运行」" : "开启「合盖后保持运行」",
                action: #selector(toggleLidAwake),
                keyEquivalent: ""
            )
            lid.target = self
            menu.addItem(lid)
        } else {
            let install = NSMenuItem(title: "安装后台助手…", action: #selector(installHelper), keyEquivalent: "")
            install.target = self
            menu.addItem(install)
        }

        let loginItem = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = login.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let diagnostics = NSMenuItem(title: "诊断…", action: #selector(showDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)

        let lockSettings = NSMenuItem(title: "打开「锁定屏幕」设置…", action: #selector(openLockSettings), keyEquivalent: "")
        lockSettings.target = self
        menu.addItem(lockSettings)

        menu.addItem(.separator())

        let update = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)

        let about = NSMenuItem(title: "关于 PowerLock…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let uninstall = NSMenuItem(title: "卸载后台助手…", action: #selector(uninstallAndQuit), keyEquivalent: "")
        uninstall.target = self
        uninstall.isEnabled = installed
        menu.addItem(uninstall)

        let quit = NSMenuItem(title: "退出 PowerLock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func addInfo(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func idleText() -> String {
        guard let idle = ScreenSaver.idleTime() else { return "未知" }
        if idle == 0 { return "不自动启动" }
        if idle % 60 == 0 { return "\(idle / 60) 分钟后启动" }
        return "\(idle) 秒后启动"
    }

    private func lidText() -> String {
        guard helper.isInstalled else { return "需要安装后台助手" }
        return store.config.lidAwake ? "已开启（仅插电）" : "已关闭"
    }

    // MARK: - 操作

    @objc private func toggleNoLock() {
        store.update { $0.noLock.toggle() }
        applyScreenSaver()
        refresh()
    }

    @objc private func toggleLidAwake() {
        store.update { $0.lidAwake.toggle() }
        refresh()
    }

    @objc private func toggleLogin() {
        if login.isEnabled {
            login.disable()
        } else {
            login.enable()
        }
        refresh()
    }

    @objc private func installHelper() {
        let result = helper.install(bundlePath: Bundle.main.bundlePath)
        if result.ok {
            store.update { $0.enabled = true }
            login.enable()
            applyScreenSaver()
            refresh()
            showAlert("已启用", "后台助手已安装，PowerLock 开始工作。", style: .informational)
        } else if !result.cancelled {
            showAlert("安装失败", result.message)
        }
    }

    /// 升级 App 后，已安装的助手可能还是旧逻辑；提示用户输入一次管理员密码更新。
    private func promptHelperUpdate() {
        let alert = NSAlert()
        alert.messageText = "需要更新后台助手"
        alert.informativeText = "PowerLock 已升级，后台助手也有更新（修复合盖时拔电不睡眠等问题）。更新需要输入一次管理员密码。"
        alert.addButton(withTitle: "现在更新")
        alert.addButton(withTitle: "稍后")
        activateApp()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        updateHelper()
    }

    @objc private func updateHelper() {
        let result = helper.install(bundlePath: Bundle.main.bundlePath)
        refresh()
        if result.ok {
            showAlert("已更新", "后台助手已更新到最新版本。", style: .informational)
        } else if !result.cancelled {
            showAlert("更新失败", result.message)
        }
    }

    @objc private func systemDidWake() {
        applyScreenSaver()
        refresh()
    }

    @objc private func showDiagnostics() {
        Diagnostics.show(config: store.config, helper: helper, login: login)
    }

    @objc private func openLockSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func checkForUpdates() {
        UpdateChecker.check { info in
            guard let info else {
                showAlert("检查更新失败", "无法获取最新版本，请稍后再试。", style: .warning)
                return
            }
            if info.version.compare(AppInfo.version, options: .numeric) == .orderedDescending {
                let alert = NSAlert()
                alert.messageText = "发现新版本 \(info.version)"
                alert.informativeText = "当前版本 \(AppInfo.version)。"
                alert.addButton(withTitle: "打开发布页")
                alert.addButton(withTitle: "稍后")
                activateApp()
                if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: info.url) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                showAlert("已是最新版本", "当前版本 \(AppInfo.version)。", style: .informational)
            }
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "PowerLock \(AppInfo.version)"
        alert.informativeText = """
        插电时保持屏幕常亮、不自动锁屏；合盖后继续运行。
        使用电池时自动恢复系统默认睡眠设置。

        后台助手：\(AppInfo.helperLabel)
        配置文件：\(AppInfo.configPath)

        说明：macOS 的「需要密码」是全局策略；PowerLock 通过保持屏幕常亮来避免自动锁屏。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        activateApp()
        alert.runModal()
    }

    @objc private func uninstallAndQuit() {
        let alert = NSAlert()
        alert.messageText = "卸载 PowerLock 后台助手？"
        alert.informativeText = "将停止并删除后台服务，恢复系统睡眠与屏幕保护设置。之后可以删除 PowerLock.app。"
        alert.addButton(withTitle: "卸载并退出")
        alert.addButton(withTitle: "取消")
        activateApp()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if helper.isInstalled {
            let result = helper.uninstall()
            if !result.ok {
                if !result.cancelled {
                    showAlert("卸载失败", result.message)
                }
                return
            }
        }
        login.disable()
        ScreenSaver.restore()
        store.update { $0.enabled = false }
        NSApp.terminate(nil)
    }
}
