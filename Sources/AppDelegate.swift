import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let store = ConfigStore()
    private let helper = HelperManager()
    private let login = LoginItemManager()
    private let power = PowerMonitor()
    private var refreshTimer: Timer?
    private var onboarding: OnboardingWindow?
    private let header = MenuHeaderView()
    private lazy var headerItem: NSMenuItem = {
        let item = NSMenuItem()
        item.view = header
        return item
    }()

    /// 助手状态要读文件：启动、菜单打开、电源变化、唤醒、安装/更新后，以及 30 秒定时器里重新读。
    private var helperInstalled = false
    private var uninstalling = false
    private var helperOutdated = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item

        _ = Legacy.migrateIfNeeded(into: store)
        Legacy.cleanup()
        if FileManager.default.fileExists(atPath: AppInfo.configPath) {
            store.update { $0.appRunning = true }
        }

        power.start()
        power.onChange { [weak self] in
            self?.reloadHelperState()
            self?.apply()
        }
        // 电量跌破下限、打开低电量模式时，助手 5 秒内就停了，图标也要跟着变
        power.onLevelChange { [weak self] in
            self?.apply()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        reloadHelperState()
        apply()

        // 兜底：助手可能在外部被删掉，屏幕保护设置也可能被系统设置改回去，定时检查一次。
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.reloadHelperState()
            self?.apply()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        if !helperInstalled {
            showOnboarding()
        } else if helperOutdated {
            DispatchQueue.main.async { [weak self] in
                self?.promptHelperUpdate()
            }
        }
    }

    /// 「不自动锁屏」需要 App 在运行：退出时恢复屏幕保护，并通知助手恢复显示器休眠，
    /// 避免卸载或退出后留下「永不启动」。合盖运行由后台助手负责，不受 App 退出影响。
    func applicationWillTerminate(_ notification: Notification) {
        guard !uninstalling else { return }
        ScreenSaver.restore()
        if FileManager.default.fileExists(atPath: AppInfo.configPath) {
            store.update { $0.appRunning = false }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 从 Finder 或 Launchpad 再次打开 App 时：没设置好就显示引导，否则弹出菜单。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reloadHelperState()
        if !helperInstalled {
            showOnboarding()
        } else {
            statusItem.button?.performClick(nil)
        }
        return false
    }

    // MARK: - 状态

    private enum Mode {
        case noHelper, helperOutdated, off, paused, active
        /// 用电池、但用户打开了「用电池时也合盖运行」且没触发任何保护
        case batteryActive
    }

    /// 两个选项都关着时，总开关开着也什么都不做，按「已关闭」显示。
    private var mode: Mode {
        let config = store.config
        if !helperInstalled { return .noHelper }
        if helperOutdated { return .helperOutdated }
        if !config.enabled || (!config.noLock && !config.lidAwake) { return .off }
        if power.isOnAC { return .active }
        return batteryLidStop() == nil ? .batteryActive : .paused
    }

    /// 用电池合盖运行为什么停着。
    private enum BatteryStop {
        case off, lowBattery(Int), lowPowerMode, unreadable, timerEnded
    }

    /// 和助手里的 battery_lid_allowed 用同样的条件，菜单显示才和实际行为一致：
    /// 只看内置电池；低电量模式用系统的判断（助手读 pmset 的 lowpowermode / powermode）。
    /// 返回 nil 表示正在运行。
    private func batteryLidStop() -> BatteryStop? {
        let config = store.config
        guard config.lidAwake, config.batteryLidAwake else { return .off }
        guard let pct = PowerMonitor.batteryPercent() else { return .unreadable }
        if pct < config.batteryFloor { return .lowBattery(pct) }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return .lowPowerMode }
        if config.batteryLidUntil > 0, Int(Date().timeIntervalSince1970) >= config.batteryLidUntil { return .timerEnded }
        return nil
    }

    /// 定时还剩多久，没设定时返回 nil。
    private func batteryTimerRemaining() -> String? {
        let until = store.config.batteryLidUntil
        guard until > 0 else { return nil }
        let minutes = max(0, (until - Int(Date().timeIntervalSince1970) + 59) / 60)
        return L.batteryTimerActive(L.durationText(minutes: minutes))
    }

    private func reloadHelperState() {
        helperInstalled = helper.isInstalled
        helperOutdated = helperInstalled && helper.needsUpdate
    }

    /// 按当前配置和电源状态设置屏幕保护，并刷新菜单栏图标。
    private func apply() {
        // 定时到了就关掉「用电池时也合盖运行」；助手那边已经按截止时间停了，这里同步菜单里的开关
        if store.config.batteryLidUntil > 0, Int(Date().timeIntervalSince1970) >= store.config.batteryLidUntil {
            store.update { $0.batteryLidAwake = false; $0.batteryLidUntil = 0 }
        }
        let config = store.config
        if helperInstalled && config.enabled && config.noLock && power.isOnAC {
            ScreenSaver.disableAutoLock()
        } else {
            ScreenSaver.restore()
        }
        refreshIcon()
    }

    private func refreshIcon() {
        let state: StatusIcon.State
        let tooltip: String
        switch mode {
        case .noHelper:
            state = .attention
            tooltip = L.tooltipAttention
        case .helperOutdated:
            state = .attention
            tooltip = L.tooltipHelperOutdated
        case .off:
            state = .off
            tooltip = L.tooltipOff
        case .paused:
            state = .paused
            tooltip = L.tooltipPaused
        case .batteryActive:
            state = .active
            tooltip = L.tooltipBatteryActive
        case .active:
            state = .active
            tooltip = L.tooltipActive
        }
        statusItem.button?.image = StatusIcon.image(state)
        statusItem.button?.toolTip = tooltip
        statusItem.button?.setAccessibilityLabel(tooltip)
    }

    // MARK: - 菜单

    func menuWillOpen(_ menu: NSMenu) {
        reloadHelperState()
        apply()
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = store.config
        let mode = self.mode

        // 状态区：一直复用同一个菜单项和 view
        header.update(tone: headerTone(mode), title: headerTitle(mode), detail: headerDetail(mode), onAC: power.isOnAC)
        menu.addItem(headerItem)
        menu.addItem(.separator())

        if mode == .noHelper {
            menu.addItem(item(L.installHelper, #selector(runSetup)))
        } else {
            // 助手需要更新时也保留开关：用户点了「稍后」，仍然可以关掉功能
            if mode == .helperOutdated {
                menu.addItem(item(L.updateHelper, #selector(updateHelper)))
                menu.addItem(.separator())
            }
            // 总开关
            let master = item(L.turnOn, #selector(toggleEnabled))
            master.state = config.enabled ? .on : .off
            menu.addItem(master)

            // 两个选项：总开关关着时置灰，但仍显示当前选择
            menu.addItem(sectionHeader(L.optionsSection))
            let noLock = item(L.optionNoLock, #selector(toggleNoLock))
            noLock.state = config.noLock ? .on : .off
            noLock.isEnabled = config.enabled
            noLock.toolTip = L.optionNoLockHint
            noLock.indentationLevel = 1
            menu.addItem(noLock)

            let lid = item(L.optionLid, #selector(toggleLidAwake))
            lid.state = config.lidAwake ? .on : .off
            lid.isEnabled = config.enabled
            lid.toolTip = L.optionLidHint
            lid.indentationLevel = 1
            menu.addItem(lid)

            // 用电池时：默认关闭，需要先开「合盖后继续运行」才可用；旧版助手不认这个设置，更新前置灰
            let batteryUsable = config.enabled && config.lidAwake && mode != .helperOutdated
            menu.addItem(sectionHeader(L.batterySection))
            let battery = item(L.batteryLid, #selector(toggleBatteryLid))
            battery.state = config.batteryLidAwake ? .on : .off
            battery.isEnabled = batteryUsable
            battery.toolTip = L.batteryLidHint
            battery.indentationLevel = 1
            menu.addItem(battery)

            let floorMenu = NSMenu()
            floorMenu.autoenablesItems = false
            for pct in PowerLockConfig.batteryFloorChoices {
                let choice = item(L.batteryFloorItem(pct), #selector(setBatteryFloor(_:)))
                choice.tag = pct
                choice.state = config.batteryFloor == pct ? .on : .off
                floorMenu.addItem(choice)
            }
            floorMenu.addItem(.separator())
            // 自定义：直接在菜单里拖滑块，每格 5%，松手保存
            floorMenu.addItem(sectionHeader(L.batteryFloorCustom))
            let sliderItem = NSMenuItem()
            sliderItem.view = FloorSliderView(current: config.batteryFloor) { [weak self] pct in
                self?.saveBatteryFloor(pct)
            }
            floorMenu.addItem(sliderItem)
            let floor = NSMenuItem(title: "\(L.batteryFloorMenu)  \(config.batteryFloor)%", action: nil, keyEquivalent: "")
            floor.submenu = floorMenu
            floorItem = floor
            floor.isEnabled = batteryUsable && config.batteryLidAwake
            floor.indentationLevel = 1
            menu.addItem(floor)

            let timerMenu = NSMenu()
            timerMenu.autoenablesItems = false
            let none = item(L.batteryTimerNone, #selector(setBatteryTimer(_:)))
            none.tag = 0
            none.state = config.batteryLidUntil == 0 ? .on : .off
            timerMenu.addItem(none)
            for hours in PowerLockConfig.batteryTimerChoices {
                let choice = item(L.batteryTimerItem(hours), #selector(setBatteryTimer(_:)))
                choice.tag = hours
                // 定时还没到期时，勾上当时选的那一项
                choice.state = config.batteryLidUntil > 0 && batteryTimerHours == hours ? .on : .off
                timerMenu.addItem(choice)
            }
            let timerTitle = batteryTimerRemaining().map { "\(L.batteryTimerMenu)  \($0)" } ?? L.batteryTimerMenu
            let timer = NSMenuItem(title: timerTitle, action: nil, keyEquivalent: "")
            timer.submenu = timerMenu
            timer.isEnabled = batteryUsable && config.batteryLidAwake
            timer.indentationLevel = 1
            menu.addItem(timer)
        }

        menu.addItem(.separator())

        let loginItem = item(L.launchAtLogin, #selector(toggleLogin))
        loginItem.state = login.isEnabled ? .on : .off
        menu.addItem(loginItem)

        // 不常用的放进子菜单
        let moreMenu = NSMenu()
        moreMenu.autoenablesItems = false
        moreMenu.addItem(item(L.lockScreenSettings, #selector(openLockSettings)))
        moreMenu.addItem(.separator())
        moreMenu.addItem(item(L.checkForUpdates, #selector(checkForUpdates)))
        moreMenu.addItem(item(L.diagnostics, #selector(showDiagnostics)))
        moreMenu.addItem(item(L.reportIssue, #selector(reportIssue)))
        moreMenu.addItem(.separator())
        let uninstall = item(L.uninstall, #selector(uninstallAndQuit))
        moreMenu.addItem(uninstall)
        let more = NSMenuItem(title: L.more, action: nil, keyEquivalent: "")
        more.submenu = moreMenu
        menu.addItem(more)

        menu.addItem(item(L.aboutItem, #selector(showAbout)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func headerTone(_ mode: Mode) -> MenuHeaderView.Tone {
        switch mode {
        case .noHelper, .helperOutdated: return .attention
        case .off: return .off
        case .paused: return .paused
        case .active, .batteryActive: return .active
        }
    }

    private func headerTitle(_ mode: Mode) -> String {
        switch mode {
        case .noHelper: return L.headerNoHelper
        case .helperOutdated: return L.headerHelperOutdated
        case .off: return L.headerOff
        case .paused: return L.headerPaused
        case .batteryActive: return L.headerBatteryActive
        case .active: return L.headerActive
        }
    }

    private func headerDetail(_ mode: Mode) -> String {
        let config = store.config
        switch mode {
        case .noHelper: return L.detailNoHelper
        case .helperOutdated: return L.detailHelperOutdated
        case .off: return L.detailOff
        case .paused:
            switch batteryLidStop() {
            case .lowBattery?: return L.detailBatteryStoppedLow(floor: config.batteryFloor)
            case .lowPowerMode?: return L.detailBatteryStoppedLPM
            case .unreadable?: return L.detailBatteryStoppedUnreadable
            case .timerEnded?, .off?, nil: return L.detailPaused
            }
        case .batteryActive:
            return L.detailBatteryActive(floor: config.batteryFloor, timer: batteryTimerRemaining())
        case .active:
            switch (config.noLock, config.lidAwake) {
            case (true, true): return L.detailActiveBoth
            case (true, false): return L.detailActiveNoLock
            case (false, true): return L.detailActiveLid
            case (false, false): return L.detailActiveNone
            }
        }
    }

    // MARK: - 操作

    @objc private func toggleEnabled() {
        store.update { $0.enabled.toggle() }
        apply()
    }

    /// 每次打开前都说明风险和自动停止的条件；关掉不用确认。
    @objc private func toggleBatteryLid() {
        if store.config.batteryLidAwake {
            store.update { $0.batteryLidAwake = false; $0.batteryLidUntil = 0 }
            apply()
            return
        }
        let alert = NSAlert()
        alert.messageText = L.batteryConfirmTitle
        alert.informativeText = L.batteryConfirmBody(floor: store.config.batteryFloor)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.batteryConfirmButton)
        alert.addButton(withTitle: L.cancel)
        activateApp()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.update { $0.batteryLidAwake = true }
        apply()
    }

    @objc private func setBatteryFloor(_ sender: NSMenuItem) {
        guard PowerLockConfig.batteryFloorRange.contains(sender.tag) else { return }
        store.update { $0.batteryFloor = sender.tag }
        apply()
    }

    /// 当前菜单里的「电量低于多少时停止」项，滑块改值后就地更新标题和勾，不重建菜单。
    private weak var floorItem: NSMenuItem?

    /// 保存电量下限并刷新菜单栏。滑块松手时调用；范围和后台助手一致（5～90）。
    private func saveBatteryFloor(_ pct: Int) {
        guard PowerLockConfig.batteryFloorRange.contains(pct), pct != store.config.batteryFloor else { return }
        store.update { $0.batteryFloor = pct }
        apply()
        // 菜单还开着时不能 rebuild（会把正在拖的滑块一起删掉），只改标题和预设档位的勾
        if let floor = floorItem {
            floor.title = "\(L.batteryFloorMenu)  \(pct)%"
            for choice in floor.submenu?.items ?? [] where choice.action == #selector(setBatteryFloor(_:)) {
                choice.state = choice.tag == pct ? .on : .off
            }
        }
        header.update(tone: headerTone(mode), title: headerTitle(mode), detail: headerDetail(mode), onAC: power.isOnAC)
    }

    /// 上次选的定时小时数，只用来在子菜单里打勾；不写进配置，App 重启后不打勾也不影响定时。
    private var batteryTimerHours = 0

    /// tag 是小时数，0 表示不限时。
    @objc private func setBatteryTimer(_ sender: NSMenuItem) {
        let hours = sender.tag
        batteryTimerHours = hours
        store.update {
            $0.batteryLidUntil = hours > 0 ? Int(Date().timeIntervalSince1970) + hours * 3600 : 0
        }
        apply()
    }

    @objc private func toggleNoLock() {
        store.update { $0.noLock.toggle() }
        apply()
    }

    @objc private func toggleLidAwake() {
        store.update {
            $0.lidAwake.toggle()
            // 用电池合盖运行依赖这个选项：关掉时一起关，以后再打开电池选项会重新确认
            if !$0.lidAwake { $0.batteryLidAwake = false; $0.batteryLidUntil = 0 }
        }
        apply()
    }

    @objc private func toggleLogin() {
        if login.isEnabled {
            login.disable()
        } else {
            login.enable()
        }
    }

    // MARK: - 首次引导与助手

    @objc private func runSetup() {
        showOnboarding()
    }

    private func showOnboarding() {
        if let onboarding {
            onboarding.show()
            return
        }
        let window = OnboardingWindow(
            onEnable: { [weak self] wantsLogin in
                guard let self else { return .failed(L.internalError) }
                let result = self.helper.install(bundlePath: Bundle.main.bundlePath)
                if result.cancelled { return .cancelled }
                guard result.ok else { return .failed(result.message) }
                self.store.update { $0.enabled = true }
                if wantsLogin { self.login.enable() }
                self.reloadHelperState()
                self.apply()
                return .installed
            },
            onFinish: { [weak self] in
                self?.onboarding = nil
            }
        )
        onboarding = window
        window.show()
    }

    /// 升级 App 后，已安装的助手可能还是旧逻辑；提示用户输入一次管理员密码更新。
    private func promptHelperUpdate() {
        let alert = NSAlert()
        alert.messageText = L.updateHelperTitle
        alert.informativeText = L.updateHelperBody
        alert.addButton(withTitle: L.updateNow)
        alert.addButton(withTitle: L.later)
        activateApp()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        updateHelper()
    }

    @objc private func updateHelper() {
        let result = helper.install(bundlePath: Bundle.main.bundlePath)
        reloadHelperState()
        apply()
        if result.ok {
            showAlert(L.helperUpdatedTitle, "", style: .informational)
        } else if !result.cancelled {
            showAlert(L.updateFailedTitle, result.message)
        }
    }

    /// 低电量模式开关时系统在任意线程发通知，切回主线程刷新。
    @objc private func powerStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.apply()
        }
    }

    @objc private func systemDidWake() {
        reloadHelperState()
        apply()
    }

    // MARK: - 更多

    @objc private func showDiagnostics() {
        Diagnostics.show(config: store.config, helper: helper, login: login)
    }

    @objc private func reportIssue() {
        NSWorkspace.shared.open(AppInfo.newIssueURL)
    }

    @objc private func openLockSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func checkForUpdates() {
        UpdateChecker.check { info in
            guard let info else {
                showAlert(L.checkUpdateFailedTitle, L.checkUpdateFailedBody)
                return
            }
            guard info.version.compare(AppInfo.version, options: .numeric) == .orderedDescending else {
                showAlert(L.upToDateTitle(info.version), L.upToDateBody(AppInfo.version), style: .informational)
                return
            }
            let brew = AppInfo.installedWithHomebrew
            let alert = NSAlert()
            alert.messageText = L.newVersionTitle(info.version)
            alert.informativeText = L.newVersionBody(current: AppInfo.version, brew: brew)
            alert.addButton(withTitle: L.openReleasePage)
            if brew { alert.addButton(withTitle: L.copyBrewCommand) }
            alert.addButton(withTitle: L.later)
            activateApp()
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if let url = URL(string: info.url) { NSWorkspace.shared.open(url) }
            case .alertSecondButtonReturn where brew:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew upgrade --cask powerlock", forType: .string)
            default:
                break
            }
        }
    }

    @objc private func showAbout() {
        AboutWindow.show()
    }

    @objc private func uninstallAndQuit() {
        let alert = NSAlert()
        alert.messageText = L.uninstallTitle
        alert.informativeText = L.uninstallBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.uninstallButton)
        alert.addButton(withTitle: L.cancel)
        activateApp()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if helper.isInstalled {
            let result = helper.uninstall()
            if !result.ok {
                if !result.cancelled {
                    showAlert(L.uninstallFailedTitle, result.message)
                }
                return
            }
        }
        login.disable()
        ScreenSaver.restore()
        // 卸载后不留用户目录下的配置；退出时也不要再写回 appRunning
        uninstalling = true
        try? FileManager.default.removeItem(atPath: AppInfo.supportDir)
        NSApp.terminate(nil)
    }
}
