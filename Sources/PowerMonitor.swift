import Foundation
import IOKit.ps

/// 使用 IOKit 电源通知，插拔瞬间响应，不用轮询 pmset。
final class PowerMonitor {
    private var runLoopSource: CFRunLoopSource?
    private var handlers: [() -> Void] = []
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

    private func powerChanged() {
        let newValue = Self.currentIsAC()
        guard newValue != isOnAC else { return }
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

}
