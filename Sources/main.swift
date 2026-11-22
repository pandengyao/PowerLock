import Cocoa

// 开发用：把各个界面渲染成 PNG，不显示窗口，不改系统设置。
if let index = CommandLine.arguments.firstIndex(of: "--render-previews") {
    let args = CommandLine.arguments
    let dir = index + 1 < args.count ? args[index + 1] : "build/previews"
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    Preview.renderAll(to: dir)
    exit(0)
}

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
