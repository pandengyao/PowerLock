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
        return (false, false, "无法创建授权脚本")
    }
    var errorInfo: NSDictionary?
    _ = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
        let number = (errorInfo["NSAppleScriptErrorNumber"] as? Int) ?? 0
        let message = (errorInfo["NSAppleScriptErrorMessage"] as? String) ?? "未知错误"
        return (false, number == -128, message)
    }
    return (true, false, "")
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
    alert.addButton(withTitle: "好")
    activateApp()
    alert.runModal()
}
