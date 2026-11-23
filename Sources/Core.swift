import Cocoa
import os

// MARK: - 应用常量

enum AppInfo {
    static let name = "PowerLock"
    static let bundleID = "com.powerlock.app"
    static let helperLabel = "com.powerlock.helper"
    static let loginLabel = "com.powerlock.login"

    static let helperPlistPath = "/Library/LaunchDaemons/com.powerlock.helper.plist"
    static let helperToolPath = "/Library/PrivilegedHelperTools/com.powerlock.helper"
    static let helperStateDir = "/Library/Application Support/PowerLock"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var supportDir: String { NSHomeDirectory() + "/Library/Application Support/PowerLock" }
    static var configPath: String { supportDir + "/config.plist" }
    static var loginAgentPath: String { NSHomeDirectory() + "/Library/LaunchAgents/\(loginLabel).plist" }

    static let repoURL = URL(string: "https://github.com/pandengyao/PowerLock")!
    static let newIssueURL = URL(string: "https://github.com/pandengyao/PowerLock/issues/new/choose")!

    /// App 是否装在 Homebrew 的 Caskroom 里（Homebrew 会把 .app 放到 /Applications，
    /// 同时在 Caskroom 留一份记录），用于检查更新时提示 brew upgrade。
    static var installedWithHomebrew: Bool {
        ["/opt/homebrew/Caskroom/powerlock", "/usr/local/Caskroom/powerlock"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// 旧版原型（local.powerlock LaunchAgent）的路径，用于一次性迁移/清理。
    static var legacyAgentPath: String { NSHomeDirectory() + "/Library/LaunchAgents/local.powerlock.plist" }
    static var legacyScriptPath: String { supportDir + "/powerlock.sh" }
    static var legacyMarkerPath: String { supportDir + "/ac-active" }
}

// MARK: - 日志

enum AppLog {
    private static let logger = Logger(subsystem: "com.powerlock.app", category: "app")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

// MARK: - 进程与授权

@discardableResult
func runProcess(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        return (-1, error.localizedDescription)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func shellQuote(_ value: String) -> String {
    if value.isEmpty { return "''" }
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func appleScriptEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

/// 通过系统管理员授权执行一次 shell 命令（仅用于安装/卸载后台助手）。
func runAsAdministrator(_ command: String) -> (ok: Bool, cancelled: Bool, message: String) {
    let source = "do shell script \"\(appleScriptEscape(command))\" with administrator privileges"
    guard let script = NSAppleScript(source: source) else {
        return (false, false, L.authScriptFailed)
    }
    var errorInfo: NSDictionary?
    _ = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
        let number = (errorInfo["NSAppleScriptErrorNumber"] as? Int) ?? 0
        let message = (errorInfo["NSAppleScriptErrorMessage"] as? String) ?? L.unknownError
        return (false, number == -128, message)
    }
    return (true, false, "")
}

/// 用户正在用的屏幕：最前面那个普通窗口（不算 PowerLock 自己的）所在的屏幕；
/// 找不到时用鼠标所在的屏幕。多显示器时，鼠标可能停在另一块屏幕上，但用户正对着的是当前应用的窗口。
/// 只读窗口位置和所属进程，不需要屏幕录制或辅助功能权限。
func screenUserIsOn() -> NSScreen? {
    let ownPID = ProcessInfo.processInfo.processIdentifier
    // CG 坐标的原点在主屏左上角、向下为正；NSScreen 的原点在主屏左下角、向上为正
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    // 列表按从前到后排列，取第一个够大的、看得见的普通窗口
    for info in windows {
        guard (info[kCGWindowLayer as String] as? Int) == 0,
              (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
              bounds.width >= 200, bounds.height >= 150 else { continue }
        let center = NSPoint(x: bounds.midX, y: primaryHeight - bounds.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen
        }
    }
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
}

extension NSWindow {
    /// 放到用户正在用的屏幕中间，略偏上（和系统 center() 的习惯一致）。
    func centerOnUserScreen() {
        guard let screen = screenUserIsOn() else {
            center()
            return
        }
        let visible = screen.visibleFrame
        var origin = NSPoint(x: visible.midX - frame.width / 2,
                             y: visible.midY - frame.height / 2 + visible.height * 0.1)
        origin.y = max(visible.minY, min(origin.y, visible.maxY - frame.height))
        origin.x = max(visible.minX, min(origin.x, visible.maxX - frame.width))
        setFrameOrigin(origin)
    }
}

/// SF Symbol。名字在当前系统上不存在时返回空图，不崩溃。
/// 注意有些名字是新系统才有的（例如 battery.75percent 要 macOS 14），最低支持 13，用之前查一下。
func symbol(_ name: String) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 16, height: 16))
}

func activateApp() {
    if #available(macOS 14.0, *) {
        NSApp.activate()
    } else {
        NSApp.activate(ignoringOtherApps: true)
    }
}

func showAlert(_ title: String, _ message: String, style: NSAlert.Style = .warning) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = style
    alert.addButton(withTitle: L.ok)
    activateApp()
    alert.runModal()
}
