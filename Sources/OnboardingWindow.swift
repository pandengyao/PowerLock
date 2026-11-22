import Cocoa

/// 首次启动引导：说明功能、权限与管理员要求，并引导安装后台助手。
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var enableButton: NSButton?
    private var errorLabel: NSTextField?
    private var loginCheckbox: NSButton?
    private var finished = false

    private let onEnable: (Bool) -> (ok: Bool, message: String)
    private let onFinish: (Bool) -> Void

    init(
        onEnable: @escaping (Bool) -> (ok: Bool, message: String),
        onFinish: @escaping (Bool) -> Void
    ) {
        self.onEnable = onEnable
        self.onFinish = onFinish
        super.init()
    }

    func show() {
        if window == nil {
            build()
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        activateApp()
    }

    private func build() {
        let size = NSSize(width: 480, height: 440)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PowerLock"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(size)
        self.window = window

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = content

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(icon)

        let title = NSTextField(labelWithString: "PowerLock")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString: "插电时保持屏幕常亮、不自动锁屏；合盖后继续运行。拔电后自动恢复系统默认。")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 420
        stack.addArrangedSubview(subtitle)

        let bullets = [
            "• 需要安装一个后台助手（管理员授权一次），之后全自动",
            "• 只修改睡眠与屏幕保护设置，不联网、不收集数据",
            "• 可随时在菜单中关闭，或一键卸载"
        ]
        for line in bullets {
            let label = NSTextField(wrappingLabelWithString: line)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = 420
            stack.addArrangedSubview(label)
        }

        let checkbox = NSButton(checkboxWithTitle: "登录时自动启动 PowerLock", target: nil, action: nil)
        checkbox.state = .on
        loginCheckbox = checkbox
        stack.addArrangedSubview(checkbox)

        let error = NSTextField(wrappingLabelWithString: "")
        error.font = .systemFont(ofSize: 11)
        error.textColor = .systemRed
        error.preferredMaxLayoutWidth = 420
        error.isHidden = true
        errorLabel = error
        stack.addArrangedSubview(error)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let enable = NSButton(title: "安装后台助手并启用", target: self, action: #selector(enableTapped))
        enable.bezelStyle = .rounded
        enable.keyEquivalent = "\r"
        enableButton = enable
        buttons.addArrangedSubview(enable)

        let later = NSButton(title: "稍后", target: self, action: #selector(laterTapped))
        later.bezelStyle = .rounded
        buttons.addArrangedSubview(later)

        stack.addArrangedSubview(buttons)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])
    }

    @objc private func enableTapped() {
        enableButton?.isEnabled = false
        errorLabel?.isHidden = true

        let wantsLogin = loginCheckbox?.state == .on
        let result = onEnable(wantsLogin)

        enableButton?.isEnabled = true
        if result.ok {
            finished = true
            window?.close()
            onFinish(true)
        } else {
            errorLabel?.stringValue = result.message
            errorLabel?.isHidden = false
        }
    }

    @objc private func laterTapped() {
        finished = true
        window?.close()
        onFinish(false)
    }

    func windowWillClose(_ notification: Notification) {
        if !finished {
            finished = true
            onFinish(false)
        }
    }
}
