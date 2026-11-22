import Cocoa

/// 首次启动引导：说明三件事和权限，安装后台助手；安装成功后显示完成页，告诉用户图标在哪。
final class OnboardingWindow: NSObject, NSWindowDelegate {
    enum Result {
        case installed, cancelled
        case failed(String)
    }

    private var window: NSWindow?
    private var enableButton: NSButton?
    private var laterButton: NSButton?
    private var spinner: NSProgressIndicator?
    private var errorLabel: NSTextField?
    private var loginCheckbox: NSButton?
    private var finished = false

    private let onEnable: (Bool) -> Result
    private let onFinish: () -> Void

    private static let width: CGFloat = 460
    private static let contentWidth: CGFloat = width - 2 * 32

    init(onEnable: @escaping (Bool) -> Result, onFinish: @escaping () -> Void) {
        self.onEnable = onEnable
        self.onFinish = onFinish
        super.init()
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
            place(introView())
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        activateApp()
    }

    // MARK: - 页面

    private func introView() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        pin(icon, size: 88)

        let title = label(L.onboardingTitle, size: 22, weight: .bold, color: .labelColor, center: true)
        let subtitle = label(L.onboardingSubtitle, size: 13, weight: .regular, color: .secondaryLabelColor, center: true)

        let features = NSStackView(views: [
            feature("bolt.fill", .systemYellow, L.featureNoLockTitle, L.featureNoLockBody),
            feature("laptopcomputer", .systemBlue, L.featureLidTitle, L.featureLidBody),
            feature("battery.75", .systemGreen, L.featureBatteryTitle, L.featureBatteryBody),
        ])
        features.orientation = .vertical
        features.alignment = .leading
        features.spacing = 14

        let privacy = label(L.onboardingPrivacy, size: 11, weight: .regular, color: .secondaryLabelColor, center: false)
        let privacyIcon = NSImageView(image: symbol("lock.shield"))
        privacyIcon.contentTintColor = .secondaryLabelColor
        privacyIcon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        let privacyRow = NSStackView(views: [privacyIcon, privacy])
        privacyRow.alignment = .top
        privacyRow.spacing = 8

        let checkbox = NSButton(checkboxWithTitle: L.onboardingLaunchAtLogin, target: nil, action: nil)
        checkbox.state = .on
        loginCheckbox = checkbox

        let error = label("", size: 11.5, weight: .regular, color: .systemRed, center: true)
        error.isHidden = true
        errorLabel = error

        let enable = NSButton(title: L.onboardingEnable, target: self, action: #selector(enableTapped))
        enable.bezelStyle = .rounded
        enable.controlSize = .large
        enable.keyEquivalent = "\r"
        enableButton = enable

        let later = NSButton(title: L.onboardingLater, target: self, action: #selector(laterTapped))
        later.bezelStyle = .rounded
        later.controlSize = .large
        later.keyEquivalent = "\u{1b}"
        laterButton = later

        let spin = NSProgressIndicator()
        spin.style = .spinning
        spin.controlSize = .small
        spin.isDisplayedWhenStopped = false
        spinner = spin

        // 主按钮固定用强调色：窗口不在前台时 macOS 会把默认按钮变灰，引导页要一直看得出该点哪个。
        enable.bezelColor = .controlAccentColor

        // 复选框单独一行，靠左；按钮一行，靠右。英文文案较长，放在同一行会被截断。
        let checkboxRow = NSStackView(views: [checkbox, NSView()])
        checkboxRow.translatesAutoresizingMaskIntoConstraints = false
        checkboxRow.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        let buttons = NSStackView(views: [NSView(), spin, later, enable])
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        let stack = NSStackView(views: [icon, title, subtitle, features, privacyRow, error, checkboxRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(16, after: icon)
        stack.setCustomSpacing(24, after: subtitle)
        stack.setCustomSpacing(22, after: features)
        stack.setCustomSpacing(18, after: privacyRow)
        stack.setCustomSpacing(10, after: error)
        stack.setCustomSpacing(14, after: checkboxRow)
        return wrap(stack, top: 40)
    }

    private func doneView() -> NSView {
        let check = NSImageView(image: symbol("checkmark.circle.fill"))
        check.symbolConfiguration = .init(pointSize: 52, weight: .regular)
        check.contentTintColor = .systemGreen

        let title = label(L.onboardingDoneTitle, size: 20, weight: .bold, color: .labelColor, center: true)
        let body = label(L.onboardingDoneBody, size: 13, weight: .regular, color: .secondaryLabelColor, center: true)

        // 菜单栏图标示意：和真实图标同一个造型，放在一块圆角底色上，像菜单栏里的一格
        let preview = NSImageView(image: StatusIcon.image(.active))
        preview.contentTintColor = .labelColor
        pin(preview, size: 18)
        let previewBox = FillView(color: .quaternaryLabelColor, cornerRadius: 7)
        previewBox.translatesAutoresizingMaskIntoConstraints = false
        previewBox.addSubview(preview)
        NSLayoutConstraint.activate([
            previewBox.widthAnchor.constraint(equalToConstant: 48),
            previewBox.heightAnchor.constraint(equalToConstant: 30),
            preview.centerXAnchor.constraint(equalTo: previewBox.centerXAnchor),
            preview.centerYAnchor.constraint(equalTo: previewBox.centerYAnchor),
        ])

        let done = NSButton(title: L.onboardingDoneButton, target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.controlSize = .large
        done.keyEquivalent = "\r"
        done.bezelColor = .controlAccentColor

        let stack = NSStackView(views: [check, title, body, previewBox, done])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(16, after: check)
        stack.setCustomSpacing(18, after: body)
        stack.setCustomSpacing(26, after: previewBox)
        return wrap(stack, top: 44)
    }

    /// 给预览截图用：不打开窗口，只返回页面内容。
    static func previewView(done: Bool) -> NSView {
        let page = OnboardingWindow(onEnable: { _ in .cancelled }, onFinish: {})
        return done ? page.doneView() : page.introView()
    }

    // MARK: - 操作

    @objc private func enableTapped() {
        setBusy(true)
        errorLabel?.isHidden = true
        let wantsLogin = loginCheckbox?.state == .on
        // 让按钮状态先画出来，再弹系统授权框（授权框是同步的）
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let result = self.onEnable(wantsLogin)
            self.setBusy(false)
            switch result {
            case .installed:
                self.place(self.doneView())
            case .cancelled:
                self.showError(L.onboardingCancelled)
            case .failed(let message):
                self.showError(message)
            }
        }
    }

    @objc private func laterTapped() {
        close()
    }

    @objc private func doneTapped() {
        close()
    }

    private func close() {
        finished = true
        window?.close()
        onFinish()
    }

    func windowWillClose(_ notification: Notification) {
        if !finished {
            finished = true
            onFinish()
        }
    }

    // MARK: - 布局工具


    private func setBusy(_ busy: Bool) {
        enableButton?.isEnabled = !busy
        laterButton?.isEnabled = !busy
        enableButton?.title = busy ? L.onboardingInstalling : L.onboardingEnable
        if busy { spinner?.startAnimation(nil) } else { spinner?.stopAnimation(nil) }
    }

    private func showError(_ message: String) {
        errorLabel?.stringValue = message
        errorLabel?.isHidden = false
        resizeToFit()
    }

    private func place(_ content: NSView) {
        window?.contentView = content
        resizeToFit()
    }

    private func wrap(_ stack: NSStackView, top: CGFloat) -> NSView {
        let content = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: top),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -26),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            content.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        return content
    }

    private func resizeToFit() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let top = window.frame.maxY
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: top - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    private func feature(_ symbolName: String, _ tint: NSColor, _ title: String, _ body: String) -> NSView {
        let icon = NSImageView(image: symbol(symbolName))
        icon.symbolConfiguration = .init(pointSize: 18, weight: .medium)
        icon.contentTintColor = tint
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let t = label(title, size: 13, weight: .semibold, color: .labelColor, center: false)
        let b = label(body, size: 12, weight: .regular, color: .secondaryLabelColor, center: false)
        b.preferredMaxLayoutWidth = Self.contentWidth - 44
        let text = NSStackView(views: [t, b])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = NSStackView(views: [icon, text])
        row.alignment = .top
        row.spacing = 12
        return row
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, center: Bool) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = center ? .center : .left
        field.preferredMaxLayoutWidth = Self.contentWidth
        field.isSelectable = false
        return field
    }

    private func pin(_ view: NSView, size: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
    }
}

/// 带圆角底色的 view。layer 底色是 CGColor，不会跟着深浅色自动变，所以在外观变化时重新取色。
final class FillView: NSView {
    private let color: NSColor

    init(color: NSColor, cornerRadius: CGFloat) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        updateColor()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }
}
