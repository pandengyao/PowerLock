import Foundation

/// 通过 com.apple.screensaver 的 idleTime 控制「启动屏幕保护程序」。
/// 只在我们实际改动过时才记录标记，避免覆盖用户自己设置的「永不」。
enum ScreenSaver {
    private static let domain = "com.apple.screensaver" as CFString
    private static var markerPath: String { AppInfo.supportDir + "/screensaver-managed" }

    static func idleTime() -> Int? {
        guard let value = CFPreferencesCopyValue(
            "idleTime" as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }

    static func lastDelayTime() -> Int {
        if let value = CFPreferencesCopyValue(
            "lastDelayTime" as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? NSNumber, value.intValue > 0 {
            return value.intValue
        }
        return 1200
    }

    static func disableAutoLock() {
        guard let current = idleTime(), current != 0 else { return }
        createMarkerIfNeeded()
        set(0)
        AppLog.info("screen saver idleTime \(current) -> 0")
    }

    static func restore() {
        guard FileManager.default.fileExists(atPath: markerPath) else { return }
        let restore = lastDelayTime()
        if idleTime() == 0 {
            set(restore)
            AppLog.info("screen saver idleTime restored to \(restore)")
        }
        try? FileManager.default.removeItem(atPath: markerPath)
    }

    static func isManaged() -> Bool {
        FileManager.default.fileExists(atPath: markerPath)
    }

    /// 旧版原型把 idleTime 设为 0 但没有留下新标记；迁移时接管这个状态，
    /// 这样拔电后仍能恢复用户原来的屏幕保护时间。
    static func adoptCurrentZero() {
        guard idleTime() == 0 else { return }
        createMarkerIfNeeded()
    }

    private static func set(_ value: Int) {
        CFPreferencesSetValue(
            "idleTime" as CFString,
            NSNumber(value: value),
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesAppSynchronize(domain)
    }

    private static func createMarkerIfNeeded() {
        guard !FileManager.default.fileExists(atPath: markerPath) else { return }
        try? FileManager.default.createDirectory(
            atPath: AppInfo.supportDir,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: markerPath, contents: Data())
    }
}
