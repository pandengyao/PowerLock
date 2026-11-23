import Cocoa

/// 开发用：`PowerLock --render-previews <目录>` 把各个界面渲染成 PNG（中英文 × 浅色/深色），
/// 不需要屏幕录制权限，也不会修改任何系统设置。README 截图和设计检查都用它。
enum Preview {
    static func renderAll(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for zh in [true, false] {
            L.isChinese = zh
            let lang = zh ? "zh" : "en"
            for dark in [false, true] {
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                let suffix = "\(lang)-\(dark ? "dark" : "light")"
                appearance.performAsCurrentDrawingAppearance {
                    render(OnboardingWindow.previewView(done: false), appearance, "\(dir)/onboarding-\(suffix).png")
                    render(OnboardingWindow.previewView(done: true), appearance, "\(dir)/onboarding-done-\(suffix).png")
                    render(AboutWindow.previewView(), appearance, "\(dir)/about-\(suffix).png")
                    render(headers(), appearance, "\(dir)/menu-header-\(suffix).png")
                    render(menuMock(zhOverride: zh), appearance, "\(dir)/menu-\(suffix).png")
                    render(moreMenuMock(), appearance, "\(dir)/menu-more-\(suffix).png")
                }
            }
        }
        print("wrote previews to \(dir)")
    }

    /// 菜单的完整模拟图：顶部状态区 + 和真实菜单相同的项目和分组。
    /// NSMenu 没有离屏渲染接口，这里按系统菜单的字号和间距画一份静态版本，只用于检查文案和结构。
    static func menuMock(zhOverride: Bool) -> NSView {
        let header = MenuHeaderView()
        header.update(tone: .active, title: L.headerActive, detail: L.detailActiveBoth, onAC: true)

        func row(_ title: String, checked: Bool = false, indent: Bool = false, enabled: Bool = true,
                 submenu: Bool = false, shortcut: String? = nil, section: Bool = false) -> NSView {
            let check = NSTextField(labelWithString: checked ? "✓" : "")
            check.font = .systemFont(ofSize: 13, weight: .semibold)
            check.translatesAutoresizingMaskIntoConstraints = false
            check.widthAnchor.constraint(equalToConstant: indent ? 30 : 18).isActive = true
            check.alignment = .right
            let label = NSTextField(labelWithString: title)
            label.font = section ? .systemFont(ofSize: 11, weight: .semibold) : .menuFont(ofSize: 13)
            label.textColor = section ? .secondaryLabelColor : (enabled ? .labelColor : .tertiaryLabelColor)
            var views: [NSView] = [check, label, NSView()]
            if submenu {
                let arrow = NSImageView(image: symbol("chevron.right"))
                arrow.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
                arrow.contentTintColor = .secondaryLabelColor
                views.append(arrow)
            }
            if let shortcut {
                let key = NSTextField(labelWithString: shortcut)
                key.font = .menuFont(ofSize: 13)
                key.textColor = .tertiaryLabelColor
                views.append(key)
            }
            let stack = NSStackView(views: views)
            stack.spacing = 6
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 14)
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.heightAnchor.constraint(equalToConstant: section ? 20 : 22).isActive = true
            stack.widthAnchor.constraint(equalToConstant: MenuHeaderView.width).isActive = true
            return stack
        }
        func separator() -> NSView {
            let line = FillView(color: .separatorColor, cornerRadius: 0)
            line.translatesAutoresizingMaskIntoConstraints = false
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
            line.widthAnchor.constraint(equalToConstant: MenuHeaderView.width - 20).isActive = true
            let wrap = NSStackView(views: [line])
            wrap.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
            return wrap
        }

        let stack = NSStackView(views: [
            header, separator(),
            row(L.turnOn, checked: true),
            row(L.optionsSection, section: true),
            row(L.optionNoLock, checked: true, indent: true),
            row(L.optionLid, checked: true, indent: true),
            separator(),
            row(L.launchAtLogin, checked: true),
            row(L.more, submenu: true),
            row(L.aboutItem),
            separator(),
            row(L.quit, shortcut: "⌘Q"),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 6, right: 0)
        return stack
    }

    static func moreMenuMock() -> NSView {
        let items = [L.lockScreenSettings, "-", L.checkForUpdates, L.diagnostics, L.reportIssue, "-", L.uninstall]
        let views: [NSView] = items.map { title in
            if title == "-" {
                let line = FillView(color: .separatorColor, cornerRadius: 0)
                line.translatesAutoresizingMaskIntoConstraints = false
                line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                line.widthAnchor.constraint(equalToConstant: 200).isActive = true
                let wrap = NSStackView(views: [line])
                wrap.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
                return wrap
            }
            let label = NSTextField(labelWithString: title)
            label.font = .menuFont(ofSize: 13)
            let row = NSStackView(views: [label])
            row.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 22).isActive = true
            return row
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        return stack
    }

    /// 五种状态的菜单顶部，竖着排在一起。
    private static func headers() -> NSView {
        let cases: [(MenuHeaderView.Tone, String, String, Bool)] = [
            (.active, L.headerActive, L.detailActiveBoth, true),
            (.paused, L.headerPaused, L.detailPaused, false),
            (.off, L.headerOff, L.detailOff, true),
            (.attention, L.headerNoHelper, L.detailNoHelper, true),
            (.attention, L.headerHelperOutdated, L.detailHelperOutdated, true),
        ]
        let stack = NSStackView(views: cases.map { tone, title, detail, ac in
            let view = MenuHeaderView()
            view.update(tone: tone, title: title, detail: detail, onAC: ac)
            return view
        })
        stack.orientation = .vertical
        stack.spacing = 1
        return stack
    }

    private static func render(_ view: NSView, _ appearance: NSAppearance, _ path: String) {
        guard let rep = bitmap(view, appearance) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// 把一个 view 按真实窗口的方式布局、按 2 倍分辨率渲染成位图。演示动画也用它。
    static func bitmap(_ view: NSView, _ appearance: NSAppearance) -> NSBitmapImageRep? {
        // 放进一个窗口里，让 Auto Layout 和外观都按真实情况生效
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        let background = NSVisualEffectView()
        background.material = .windowBackground
        background.state = .active
        background.blendingMode = .behindWindow
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        let size = container.fittingSize
        window.setContentSize(size)
        container.frame = NSRect(origin: .zero, size: size)
        container.layoutSubtreeIfNeeded()
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        container.cacheDisplay(in: container.bounds, to: rep)
        return rep
    }
}
