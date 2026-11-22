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

    /// 已安装助手的逻辑版本；1.0.x 的助手没有版本号，按 1 处理。
    var installedVersion: Int? {
        guard isInstalled else { return nil }
        return Self.scriptVersion(atPath: AppInfo.helperToolPath) ?? 1
    }

    /// App 内置助手的逻辑版本。
    var bundledVersion: Int? {
        guard let directory = helperDirectory else { return nil }
        return Self.scriptVersion(atPath: directory + "/powerlock-helper.sh")
    }

    /// 已安装的助手比 App 内置的旧，需要重新安装（升级 App 后出现）。
    var needsUpdate: Bool {
        guard let installed = installedVersion, let bundled = bundledVersion else { return false }
        return bundled > installed
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

    /// 从助手脚本里读 `readonly HELPER_VERSION=<n>`。
    private static func scriptVersion(atPath path: String) -> Int? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("readonly HELPER_VERSION=") else { continue }
            return Int(trimmed.dropFirst("readonly HELPER_VERSION=".count))
        }
        return nil
    }
}
