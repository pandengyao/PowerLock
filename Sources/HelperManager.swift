import Foundation

/// 管理随 App 内置、由 App 安装到系统的 root 助手。
final class HelperManager {
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: AppInfo.helperPlistPath) &&
        FileManager.default.fileExists(atPath: AppInfo.helperToolPath)
    }

    var isRunning: Bool {
        if runProcess("/bin/launchctl", ["print", "system/\(AppInfo.helperLabel)"]).status == 0 {
            return true
        }
        return runProcess("/usr/bin/pgrep", ["-f", AppInfo.helperToolPath]).status == 0
    }

    func install(bundlePath: String) -> (ok: Bool, cancelled: Bool, message: String) {
        guard let directory = helperDirectory else {
            return (false, false, "找不到内置的助手资源")
        }
        let script = directory + "/install-helper.sh"
        guard FileManager.default.fileExists(atPath: script) else {
            return (false, false, "安装脚本缺失：\(script)")
        }
        let command = "/bin/zsh \(shellQuote(script)) \(shellQuote(bundlePath))"
        AppLog.info("installing helper from \(bundlePath)")
        return runAsAdministrator(command)
    }

    func uninstall() -> (ok: Bool, cancelled: Bool, message: String) {
        guard let directory = helperDirectory else {
            return (false, false, "找不到内置的助手资源")
        }
        let script = directory + "/uninstall-helper.sh"
        guard FileManager.default.fileExists(atPath: script) else {
            return (false, false, "卸载脚本缺失：\(script)")
        }
        return runAsAdministrator("/bin/zsh \(shellQuote(script))")
    }

    private var helperDirectory: String? {
        Bundle.main.resourceURL?.appendingPathComponent("Helper").path
    }
}
