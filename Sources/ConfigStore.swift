import Foundation

struct PowerLockConfig: Equatable {
    var enabled: Bool = false
    var noLock: Bool = true
    var lidAwake: Bool = true
}

/// 用户配置：~/Library/Application Support/PowerLock/config.plist
/// 后台助手以 root 读取同一文件；只包含布尔值，助手会严格校验。
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
            "lidAwake": config.lidAwake
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
        return config
    }
}
