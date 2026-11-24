import Cocoa

/// 诊断信息：给反馈问题用，内容固定用英文，方便维护者阅读，也便于搜索。
enum Diagnostics {
    private static var window: NSWindow?
    private static var textView: NSTextView?
    private static var copyButton: NSButton?
    private static var context: (HelperManager, LoginItemManager)?

    static func summary(config: PowerLockConfig, helper: HelperManager, login: LoginItemManager) -> String {
        var lines: [String] = []
        lines.append("PowerLock \(AppInfo.version) (\(AppInfo.build))")
        let os = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        lines.append("Arch: \(architecture)")
        lines.append("Model: \(hardwareModel)")
        lines.append("Language: \(Locale.preferredLanguages.first ?? "-")")
        lines.append("Installed with Homebrew: \(AppInfo.installedWithHomebrew)")
        lines.append("")
        lines.append("Power source: \(PowerMonitor.currentIsAC() ? "AC" : "Battery")")
        lines.append("Helper installed: \(helper.isInstalled)")
        lines.append("Helper running: \(helper.isRunning)")
        lines.append("Helper version: installed \(helper.installedVersion.map(String.init) ?? "-"), bundled \(helper.bundledVersion.map(String.init) ?? "-")")
        lines.append("Launch at login: \(login.isEnabled)")
        lines.append("")
        lines.append("Config: enabled=\(config.enabled) noLock=\(config.noLock) lidAwake=\(config.lidAwake) appRunning=\(config.appRunning)")
        lines.append("Battery lid: on=\(config.batteryLidAwake) floor=\(config.batteryFloor)% until=\(config.batteryLidUntil) level=\(PowerMonitor.batteryPercent().map { "\($0)%" } ?? "n/a") lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
        lines.append("Screen saver idleTime: \(ScreenSaver.idleTime().map(String.init) ?? "default")")
        lines.append("Screen saver managed by PowerLock: \(ScreenSaver.isManaged())")
        lines.append("")
        lines.append("Lid: \(lidState)")
        lines.append("")
        lines.append("pmset -g:")
        lines.append(runProcess("/usr/bin/pmset", ["-g"]).output.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("")
        lines.append("pmset -g custom (AC Power):")
        let custom = runProcess("/usr/bin/pmset", ["-g", "custom"]).output
        if let range = custom.range(of: "AC Power:") {
            lines.append(String(custom[range.lowerBound...].prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.joined(separator: "\n")
    }

    static func show(config: PowerLockConfig, helper: HelperManager, login: LoginItemManager) {
        context = (helper, login)
        let text = summary(config: config, helper: helper, login: login)

        if let window, let textView {
            textView.string = text
            window.makeKeyAndOrderFront(nil)
            activateApp()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L.diagnosticsTitle
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 320)

        let hint = NSTextField(wrappingLabelWithString: L.diagnosticsHint)
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .lineBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = text
        scroll.documentView = textView

        let issue = NSButton(title: L.openIssue, target: Handler.shared, action: #selector(Handler.openIssue))
        issue.bezelStyle = .rounded
        let refresh = NSButton(title: L.refresh, target: Handler.shared, action: #selector(Handler.refresh))
        refresh.bezelStyle = .rounded
        let copy = NSButton(title: L.copy, target: Handler.shared, action: #selector(Handler.copyText))
        copy.bezelStyle = .rounded
        copy.keyEquivalent = "\r"
        copyButton = copy

        let buttons = NSStackView(views: [issue, NSView(), refresh, copy])
        buttons.distribution = .fill

        let stack = NSStackView(views: [hint, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            buttons.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
        window.contentView = content
        window.centerOnUserScreen()
        window.makeKeyAndOrderFront(nil)
        activateApp()

        self.window = window
        self.textView = textView
    }

    /// NSButton 需要一个 NSObject 作为 target。
    private final class Handler: NSObject {
        static let shared = Handler()

        @objc func copyText() {
            guard let text = Diagnostics.textView?.string else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            Diagnostics.copyButton?.title = L.copied
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Diagnostics.copyButton?.title = L.copy
            }
        }

        /// 重新读配置文件，拿到最新状态。
        @objc func refresh() {
            guard let (helper, login) = Diagnostics.context else { return }
            Diagnostics.textView?.string = Diagnostics.summary(config: ConfigStore().config, helper: helper, login: login)
        }

        @objc func openIssue() {
            NSWorkspace.shared.open(AppInfo.newIssueURL)
        }
    }

    private static var lidState: String {
        let out = runProcess("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "1"]).output
        guard out.contains("AppleClamshellState") else { return "no lid" }
        let closed = out.contains("\"AppleClamshellState\" = Yes")
        let causesSleep = out.contains("\"AppleClamshellCausesSleep\" = Yes")
        return "closed=\(closed) causesSleep=\(causesSleep)"
    }

    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "-" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
