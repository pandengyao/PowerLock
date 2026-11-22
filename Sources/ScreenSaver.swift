import Foundation

/// 通过 com.apple.screensaver 的 idleTime 控制「启动屏幕保护程序」。
/// 只在我们实际改动过时才记录标记，避免覆盖用户自己设置的「永不」。
/// 标记文件内容：改动前的秒数；原来没有这个键（系统默认）时写 `default`；
/// 1.0.x 留下的是空文件。
enum ScreenSaver {
    private static let domain = "com.apple.screensaver" as CFString
    private static var markerPath: String { AppInfo.supportDir + "/screensaver-managed" }
    private static let systemDefaultMarker = "default"

    private enum Original {
        case seconds(Int)
        case systemDefault
        case unknown
    }

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

    static func disableAutoLock() {
        let current = idleTime()
        // 用户自己设成「永不」时不接管，也不留标记。
        if current == 0 { return }
        createMarkerIfNeeded(original: current)
        set(0)
        AppLog.info("screen saver idleTime \(current.map(String.init) ?? "default") -> 0")
    }

    static func restore() {
        guard FileManager.default.fileExists(atPath: markerPath) else { return }
        // 如果用户在接管期间自己改过，就不再覆盖。
        if idleTime() == 0 {
            var restoreTo: Int?
            switch savedOriginal() {
            case .seconds(let value):
                restoreTo = value
            case .systemDefault:
                restoreTo = nil
            case .unknown:
                // 1.0.x 没记原值；系统把选「永不」之前的时间存在 lastDelayTime。
                restoreTo = lastDelayTime()
            }
            set(restoreTo)
            AppLog.info("screen saver idleTime restored to \(restoreTo.map(String.init) ?? "system default")")
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
        createMarkerIfNeeded(original: lastDelayTime() ?? 1200)
    }

    private static func savedOriginal() -> Original {
        guard let data = FileManager.default.contents(atPath: markerPath),
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .unknown
        }
        if text == systemDefaultMarker { return .systemDefault }
        if let value = Int(text), value > 0 { return .seconds(value) }
        return .unknown
    }

    /// 没有记录时返回 nil，恢复时删除 idleTime，回到系统默认。
    private static func lastDelayTime() -> Int? {
        guard let value = CFPreferencesCopyValue(
            "lastDelayTime" as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? NSNumber, value.intValue > 0 else {
            return nil
        }
        return value.intValue
    }

    private static func set(_ value: Int?) {
        CFPreferencesSetValue(
            "idleTime" as CFString,
            value.map { NSNumber(value: $0) },
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    private static func createMarkerIfNeeded(original: Int?) {
        guard !FileManager.default.fileExists(atPath: markerPath) else { return }
        try? FileManager.default.createDirectory(
            atPath: AppInfo.supportDir,
            withIntermediateDirectories: true
        )
        let content = original.map { String($0) } ?? systemDefaultMarker
        FileManager.default.createFile(atPath: markerPath, contents: Data(content.utf8))
    }
}
