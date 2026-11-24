import Foundation
import IOKit.ps

/// 使用 IOKit 电源通知，插拔瞬间响应，不用轮询 pmset。
final class PowerMonitor {
    private var runLoopSource: CFRunLoopSource?
    private var handlers: [() -> Void] = []
    private var levelHandlers: [() -> Void] = []
    private(set) var isOnAC: Bool

    init() {
        isOnAC = Self.currentIsAC()
    }

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.powerChanged()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            AppLog.error("无法创建电源通知源")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    func onChange(_ handler: @escaping () -> Void) {
        handlers.append(handler)
    }

    /// 电源没切换、只是电量等信息变了（用电池时）。
    func onLevelChange(_ handler: @escaping () -> Void) {
        levelHandlers.append(handler)
    }

    private func powerChanged() {
        let newValue = Self.currentIsAC()
        guard newValue != isOnAC else {
            if !newValue { levelHandlers.forEach { $0() } }
            return
        }
        isOnAC = newValue
        AppLog.info("power source changed: \(newValue ? "AC" : "Battery")")
        handlers.forEach { $0() }
    }

    static func currentIsAC() -> Bool {
        guard let type = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String? else {
            return false
        }
        return type == "AC Power"
    }

    /// 内置电池的电量百分比（0～100）；没有电池或读不到时返回 nil。
    static func batteryPercent() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return Swift.min(100, Swift.max(0, current * 100 / max))
        }
        return nil
    }

}
