import Cocoa

/// 关于窗口：图标、版本、一句话介绍、GitHub 和许可链接。
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            activateApp()
            return
        }

        let content = makeContent()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        activateApp()
        self.window = window
    }

    /// 给预览截图用。
    static func previewView() -> NSView { makeContent() }

    private static func makeContent() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let name = NSTextField(labelWithString: "PowerLock")
        name.font = .systemFont(ofSize: 20, weight: .bold)

        let version = NSTextField(labelWithString: "\(AppInfo.version) (\(AppInfo.build))")
        version.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        version.textColor = .secondaryLabelColor
        version.isSelectable = true

        let tagline = NSTextField(wrappingLabelWithString: L.aboutTagline)
        tagline.font = .systemFont(ofSize: 12)
        tagline.textColor = .secondaryLabelColor
        tagline.alignment = .center
        tagline.preferredMaxLayoutWidth = 260

        let links = NSStackView(views: [
            link(L.aboutGitHub, AppInfo.repoURL),
            dotSeparator(),
            link(L.aboutLicense, AppInfo.repoURL.appendingPathComponent("blob/main/LICENSE")),
        ])
        links.spacing = 6

        let stack = NSStackView(views: [icon, name, version, tagline, links])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(12, after: icon)
        stack.setCustomSpacing(14, after: version)
        stack.setCustomSpacing(16, after: tagline)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 34),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            content.widthAnchor.constraint(equalToConstant: 320),
        ])
        return content
    }

    private static func link(_ title: String, _ url: URL) -> NSButton {
        let button = LinkButton(title: title, url: url)
        return button
    }

    private static func dotSeparator() -> NSTextField {
        let dot = NSTextField(labelWithString: "·")
        dot.textColor = .tertiaryLabelColor
        return dot
    }
}

/// 看起来像链接的按钮，点击用浏览器打开。
final class LinkButton: NSButton {
    private let url: URL

    init(title: String, url: URL) {
        self.url = url
        super.init(frame: .zero)
        isBordered = false
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: 12),
        ])
        target = self
        action = #selector(open)
        setAccessibilityRole(.link)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    @objc private func open() {
        NSWorkspace.shared.open(url)
    }
}
