import Cocoa

// 便于脚本/CI 检查运行状态，不启动 UI。
if CommandLine.arguments.contains("--status") {
    let store = ConfigStore()
    let helper = HelperManager()
    let login = LoginItemManager()
    print(Diagnostics.summary(config: store.config, helper: helper, login: login))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
