import Foundation

/// 登录时自动启动 PowerLock。
/// 未签名阶段使用用户级 LaunchAgent（可靠且不需要额外权限）；
/// 后续拿到签名后可迁移到 SMAppService.mainApp。
final class LoginItemManager {
    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: AppInfo.loginAgentPath)
    }

    func enable() {
        let plist: [String: Any] = [
            "Label": AppInfo.loginLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]
        do {
            try FileManager.default.createDirectory(
                atPath: NSHomeDirectory() + "/Library/LaunchAgents",
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: URL(fileURLWithPath: AppInfo.loginAgentPath), options: .atomic)
        } catch {
            AppLog.error("写入登录项失败: \(error.localizedDescription)")
            return
        }
        _ = runProcess("/bin/launchctl", ["bootout", "gui/\(getuid())/\(AppInfo.loginLabel)"])
        let result = runProcess(
            "/bin/launchctl",
            ["bootstrap", "gui/\(getuid())", AppInfo.loginAgentPath]
        )
        if result.status != 0 {
            AppLog.error("加载登录项失败: \(result.output)")
        }
    }

    func disable() {
        _ = runProcess("/bin/launchctl", ["bootout", "gui/\(getuid())/\(AppInfo.loginLabel)"])
        try? FileManager.default.removeItem(atPath: AppInfo.loginAgentPath)
    }
}
