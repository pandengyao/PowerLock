import Cocoa

enum Diagnostics {
    private static var window: NSWindow?
    private static var textView: NSTextView?

    static func summary(config: PowerLockConfig, helper: HelperManager, login: LoginItemManager) -> String {
        var lines: [String] = []
        lines.append("PowerLock \(AppInfo.version) (\(AppInfo.build))")
        lines.append("Bundle ID: \(AppInfo.bundleID)")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Arch: \(architecture)")
        lines.append("")
        lines.append("电源: \(PowerMonitor.label())")
        lines.append("助手已安装: \(helper.isInstalled)")
        lines.append("助手运行中: \(helper.isRunning)")
        lines.append("助手版本: 已安装 \(helper.installedVersion.map(String.init) ?? "-")，内置 \(helper.bundledVersion.map(String.init) ?? "-")")
        lines.append("助手 plist: \(AppInfo.helperPlistPath)")
        lines.append("助手程序: \(AppInfo.helperToolPath)")
        lines.append("登录项: \(login.isEnabled)")
        lines.append("")
        lines.append("配置 enabled: \(config.enabled)")
        lines.append("配置 noLock: \(config.noLock)")
        lines.append("配置 lidAwake: \(config.lidAwake)")
        lines.append("配置 appRunning: \(config.appRunning)")
        lines.append("配置路径: \(AppInfo.configPath)")
        lines.append("")
        lines.append("屏幕保护 idleTime: \(ScreenSaver.idleTime().map(String.init) ?? "未知")")
        lines.append("屏幕保护被接管: \(ScreenSaver.isManaged())")
        lines.append("")
        lines.append("pmset -g:")
        lines.append(runProcess("/usr/bin/pmset", ["-g"]).output.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("")
        lines.append("pmset -g custom (AC Power):")
        let custom = runProcess("/usr/bin/pmset", ["-g", "custom"]).output
        if let range = custom.range(of: "AC Power:") {
            lines.append(String(custom[range.lowerBound...].prefix(500)))
        }
        return lines.joined(separator: "\n")
    }

    static func show(config: PowerLockConfig, helper: HelperManager, login: LoginItemManager) {
        let text = summary(config: config, helper: helper, login: login)

        if let window, let textView {
            textView.string = text
            window.makeKeyAndOrderFront(nil)
            activateApp()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PowerLock 诊断"
        window.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = text
        scroll.documentView = textView

        window.contentView?.addSubview(scroll)
        window.center()
        window.makeKeyAndOrderFront(nil)
        activateApp()

        self.window = window
        self.textView = textView
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
