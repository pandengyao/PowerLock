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
        }
        // 只写 plist，不立即 bootstrap：launchd 下次登录时会自动加载 ~/Library/LaunchAgents。
        // 立即加载会因为 RunAtLoad 马上执行 open -a，正在运行的 App 收到 reopen 事件，菜单会自己弹出来。
    }

    func disable() {
        _ = runProcess("/bin/launchctl", ["bootout", "gui/\(getuid())/\(AppInfo.loginLabel)"])
        try? FileManager.default.removeItem(atPath: AppInfo.loginAgentPath)
    }
}
