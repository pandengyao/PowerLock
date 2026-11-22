import Foundation

/// 旧原型（local.powerlock LaunchAgent + powerlock.sh）的一次性迁移与清理。
enum Legacy {
    static func exists() -> Bool {
        FileManager.default.fileExists(atPath: AppInfo.legacyAgentPath)
    }

    /// 在写入新配置之前调用，把旧版开启状态迁移过来。
    @discardableResult
    static func migrateIfNeeded(into store: ConfigStore) -> Bool {
        guard exists() else { return false }
        guard !FileManager.default.fileExists(atPath: AppInfo.configPath) else { return false }

        store.update {
            $0.enabled = true
            $0.noLock = true
            $0.lidAwake = sleepDisabled()
        }
        ScreenSaver.adoptCurrentZero()
        AppLog.info("migrated legacy PowerLock settings")
        return true
    }

    /// 删除旧版 LaunchAgent 与脚本，避免和新助手重复工作。
    static func cleanup() {
        guard exists() else { return }
        _ = runProcess("/bin/launchctl", ["bootout", "gui/\(getuid())/local.powerlock"])
        try? FileManager.default.removeItem(atPath: AppInfo.legacyAgentPath)
        try? FileManager.default.removeItem(atPath: AppInfo.legacyScriptPath)
        try? FileManager.default.removeItem(atPath: AppInfo.legacyMarkerPath)
        AppLog.info("cleaned up legacy PowerLock agent")
    }

    static func sleepDisabled() -> Bool {
        let output = runProcess("/usr/bin/pmset", ["-g"]).output
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled", parts[1] == "1" {
                return true
            }
        }
        return false
    }
}
