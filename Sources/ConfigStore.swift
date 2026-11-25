import Foundation

struct PowerLockConfig: Equatable {
    var enabled: Bool = false
    var noLock: Bool = true
    var lidAwake: Bool = true
    /// App 是否在运行。屏幕保护由 App 管理，App 退出后助手也恢复显示器休眠，两者保持一致。
    var appRunning: Bool = true
    /// 用电池时也合盖运行。默认关闭：合盖散热差，电量也容易耗光，要用户自己打开。
    var batteryLidAwake: Bool = false
    /// 用电池合盖运行时，电量降到这个百分比就恢复睡眠。助手只接受 5～90。
    var batteryFloor: Int = 20
    /// 用电池合盖运行的截止时间（Unix 秒）。0 表示不限时。
    var batteryLidUntil: Int = 0

    static let batteryFloorChoices = [10, 20, 30, 50, 80]
    /// 后台助手接受的电量下限范围（powerlock-helper.sh 里的 read_int batteryFloor 5 90）
    static let batteryFloorRange = 5...90
    static let batteryTimerChoices = [1, 2, 4]   // 小时
}

/// 用户配置：~/Library/Application Support/PowerLock/config.plist
/// 后台助手以 root 读取同一文件；只包含布尔值和整数，助手会校验类型和范围。
final class ConfigStore {
    private(set) var config: PowerLockConfig

    init() {
        config = Self.read() ?? PowerLockConfig()
    }

    func update(_ mutate: (inout PowerLockConfig) -> Void) {
        mutate(&config)
        save()
    }

    func save() {
        let dictionary: [String: Any] = [
            "enabled": config.enabled,
            "noLock": config.noLock,
            "lidAwake": config.lidAwake,
            "appRunning": config.appRunning,
            "batteryLidAwake": config.batteryLidAwake,
            "batteryFloor": config.batteryFloor,
            "batteryLidUntil": config.batteryLidUntil
        ]
        do {
            try FileManager.default.createDirectory(
                atPath: AppInfo.supportDir,
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: dictionary,
                format: .xml,
                options: 0
            )
            try data.write(to: URL(fileURLWithPath: AppInfo.configPath), options: .atomic)
        } catch {
            AppLog.error("保存配置失败: \(error.localizedDescription)")
        }
    }

    private static func read() -> PowerLockConfig? {
        guard let data = FileManager.default.contents(atPath: AppInfo.configPath),
              let object = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        var config = PowerLockConfig()
        if let value = dictionary["enabled"] as? Bool { config.enabled = value }
        if let value = dictionary["noLock"] as? Bool { config.noLock = value }
        if let value = dictionary["lidAwake"] as? Bool { config.lidAwake = value }
        if let value = dictionary["appRunning"] as? Bool { config.appRunning = value }
        if let value = dictionary["batteryLidAwake"] as? Bool { config.batteryLidAwake = value }
        if let value = integer(dictionary["batteryFloor"]), PowerLockConfig.batteryFloorRange.contains(value) { config.batteryFloor = value }
        // 和助手一致：没有这个键表示不限时；有但不合法时按已到期处理（1 是过去的时间），不能变成不限时
        if dictionary["batteryLidUntil"] != nil {
            if let value = integer(dictionary["batteryLidUntil"]), (0...4_102_444_800).contains(value) {
                config.batteryLidUntil = value
            } else {
                config.batteryLidUntil = 1
            }
        }
        return config
    }

    /// 和助手的 read_int 一致：只认 plist 的 <integer>，布尔值和小数都不算。
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID(),
              !CFNumberIsFloatType(number) else { return nil }
        return number.intValue
    }
}
