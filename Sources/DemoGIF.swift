import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 开发用：`PowerLock --render-demo <输出.gif> [zh|en]` 生成 README 里的演示动画。
/// 用真实的菜单栏图标和菜单顶部状态区，按「插电 → 拔电 → 打开电池选项 → 插回 → 关闭」的顺序切换，
/// 和 --render-previews 一样离屏渲染，不需要屏幕录制权限，也不改系统设置。
enum DemoGIF {
    private struct Scene {
        let icon: StatusIcon.State
        let tone: MenuHeaderView.Tone
        let title: String
        let detail: String
        let onAC: Bool
        let enabled: Bool
        /// 「用电池时 → 也合盖运行」是否打开
        let batteryLid: Bool
        let caption: String
        let seconds: Double
    }

    static func render(to path: String) {
        let scenes: [Scene] = [
            Scene(icon: .active, tone: .active, title: L.headerActive, detail: L.detailActiveBoth,
                  onAC: true, enabled: true, batteryLid: false, caption: L.demoCaptionPlugged, seconds: 3.2),
            Scene(icon: .paused, tone: .paused, title: L.headerPaused, detail: L.detailPaused,
                  onAC: false, enabled: true, batteryLid: false, caption: L.demoCaptionUnplugged, seconds: 3.2),
            Scene(icon: .active, tone: .active, title: L.headerBatteryActive,
                  detail: L.detailBatteryActive(floor: 20, timer: nil),
                  onAC: false, enabled: true, batteryLid: true, caption: L.demoCaptionBattery, seconds: 3.6),
            Scene(icon: .active, tone: .active, title: L.headerActive, detail: L.detailActiveBoth,
                  onAC: true, enabled: true, batteryLid: true, caption: L.demoCaptionPluggedBack, seconds: 2.6),
            Scene(icon: .off, tone: .off, title: L.headerOff, detail: L.detailOff,
                  onAC: true, enabled: false, batteryLid: true, caption: L.demoCaptionOff, seconds: 2.6),
        ]

        let size = NSSize(width: 640, height: 440)
        let scale: CGFloat = 1.5
        let fps = 12.0
        let fadeFrames = 5

        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                         UTType.gif.identifier as CFString,
                                                         frameCount(scenes, fps), nil) else {
            print("cannot create \(path)")
            return
        }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0],
        ] as CFDictionary)

        let light = NSAppearance(named: .aqua)!
        var previous: CGImage?
        for scene in scenes {
            var frame: CGImage?
            light.performAsCurrentDrawingAppearance {
                frame = draw(scene, size: size, scale: scale)
            }
            guard let current = frame else { continue }
            // 场景切换时淡入，看得出是同一个菜单在变
            if let previous {
                for i in 1...fadeFrames {
                    let t = CGFloat(i) / CGFloat(fadeFrames + 1)
                    add(blend(previous, current, t), to: dest, delay: 1 / fps)
                }
            }
            let hold = max(1, Int(scene.seconds * fps) - (previous == nil ? 0 : fadeFrames))
            // 静止帧合成一帧，用更长的停留时间，文件小很多
            add(current, to: dest, delay: Double(hold) / fps)
            previous = current
        }
        if CGImageDestinationFinalize(dest) {
            print("wrote \(path)")
        }
    }

    private static func frameCount(_ scenes: [Scene], _ fps: Double) -> Int {
        scenes.count + (scenes.count - 1) * 5
    }

    private static func add(_ image: CGImage, to dest: CGImageDestination, delay: Double) {
        CGImageDestinationAddImage(dest, image, [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delay,
                kCGImagePropertyGIFUnclampedDelayTime as String: delay,
            ],
        ] as CFDictionary)
    }

    private static func blend(_ a: CGImage, _ b: CGImage, _ t: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: a.width, height: a.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: a.width, height: a.height)
        ctx.draw(a, in: rect)
        ctx.setAlpha(t)
        ctx.draw(b, in: rect)
        return ctx.makeImage()!
    }

    /// 一帧：桌面背景、菜单栏（含 PowerLock 图标和电源图标）、展开的菜单、底部说明文字。
    private static func draw(_ scene: Scene, size: NSSize, scale: CGFloat) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let W = size.width, H = size.height
        func rect(_ x: CGFloat, top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x, y: H - top - h, width: w, height: h)
        }

        // 桌面
        NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.55, blue: 0.93, alpha: 1),
                   ending: NSColor(srgbRed: 0.17, green: 0.29, blue: 0.72, alpha: 1))!
            .draw(in: NSRect(origin: .zero, size: size), angle: -60)

        // 菜单栏
        let barH: CGFloat = 26
        NSColor(white: 1, alpha: 0.78).setFill()
        rect(0, top: 0, W, barH).fill()
        let barFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let clock = NSAttributedString(string: L.isChinese ? "11月25日 周三  10:42" : "Wed Nov 25  10:42 AM",
                                       attributes: [.font: barFont, .foregroundColor: NSColor(white: 0.1, alpha: 1)])
        clock.draw(at: NSPoint(x: W - 16 - clock.size().width, y: H - barH + (barH - clock.size().height) / 2))
        var x = W - 30 - clock.size().width
        // 电源图标：插电时带闪电的电池，用电池时普通电池
        let battery = symbol(scene.onAC ? "battery.100.bolt" : "battery.75")
        let batteryRect = rect(x - 30, top: 5, 26, 16)
        tinted(battery, NSColor(white: 0.1, alpha: 1)).draw(in: batteryRect)
        x -= 50
        // PowerLock 图标，带按下时的高亮底
        let itemRect = rect(x - 30, top: 2, 30, 22)
        NSColor(white: 0, alpha: 0.12).setFill()
        NSBezierPath(roundedRect: itemRect, xRadius: 5, yRadius: 5).fill()
        tinted(StatusIcon.image(scene.icon), NSColor(white: 0.1, alpha: 1))
            .draw(in: NSRect(x: itemRect.midX - 9, y: itemRect.midY - 9, width: 18, height: 18))

        // 展开的菜单：真实的状态区 view + 总开关 + 插电时两个选项 + 用电池时三行
        // 菜单用和截图相同的渲染方式（Preview.bitmap），颜色和图标与 README 截图一致
        let menuRepOpt = Preview.bitmap(menuView(scene), NSAppearance(named: .aqua)!)
        let menuSize = menuRepOpt?.size ?? .zero
        let menuRect = rect(itemRect.maxX - menuSize.width + 12, top: barH + 6, menuSize.width, menuSize.height)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: menuRect, xRadius: 10, yRadius: 10).fill()
        NSGraphicsContext.restoreGraphicsState()
        if let menuRep = menuRepOpt {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: menuRect, xRadius: 10, yRadius: 10).addClip()
            menuRep.draw(in: menuRect)
            NSGraphicsContext.restoreGraphicsState()
        }

        // 底部说明
        let caption = NSAttributedString(string: scene.caption, attributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let pillW = caption.size().width + 40, pillH: CGFloat = 44
        let pill = rect(28, top: H - 28 - pillH, pillW, pillH)
        NSColor(white: 0, alpha: 0.32).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2).fill()
        caption.draw(at: NSPoint(x: pill.minX + 20, y: pill.midY - caption.size().height / 2))

        return rep.cgImage
    }

    private static func menuView(_ scene: Scene) -> NSView {
        let header = MenuHeaderView()
        header.update(tone: scene.tone, title: scene.title, detail: scene.detail, onAC: scene.onAC)

        func row(_ title: String, checked: Bool, indent: Bool, enabled: Bool, submenu: Bool = false) -> NSView {
            let check = NSTextField(labelWithString: checked ? "✓" : "")
            check.font = .systemFont(ofSize: 13, weight: .semibold)
            check.textColor = enabled ? .labelColor : .tertiaryLabelColor
            check.alignment = .right
            check.translatesAutoresizingMaskIntoConstraints = false
            check.widthAnchor.constraint(equalToConstant: indent ? 30 : 18).isActive = true
            let label = NSTextField(labelWithString: title)
            label.font = .menuFont(ofSize: 13)
            label.textColor = enabled ? .labelColor : .tertiaryLabelColor
            var views: [NSView] = [check, label, NSView()]
            if submenu {
                let arrow = NSImageView(image: symbol("chevron.right"))
                arrow.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
                arrow.contentTintColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
                views.append(arrow)
            }
            let stack = NSStackView(views: views)
            stack.spacing = 6
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 14)
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.heightAnchor.constraint(equalToConstant: 22).isActive = true
            stack.widthAnchor.constraint(equalToConstant: MenuHeaderView.width).isActive = true
            return stack
        }
        func sectionRow(_ title: String) -> NSView {
            let section = NSTextField(labelWithString: title)
            section.font = .systemFont(ofSize: 11, weight: .semibold)
            section.textColor = .secondaryLabelColor
            let wrap = NSStackView(views: [section])
            wrap.edgeInsets = NSEdgeInsets(top: 2, left: 24, bottom: 0, right: 0)
            return wrap
        }
        let batteryUsable = scene.enabled
        let batterySubUsable = scene.enabled && scene.batteryLid

        let line = FillView(color: .separatorColor, cornerRadius: 0)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        line.widthAnchor.constraint(equalToConstant: MenuHeaderView.width - 20).isActive = true
        let separator = NSStackView(views: [line])
        separator.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)

        let stack = NSStackView(views: [
            header, separator,
            row(L.turnOn, checked: scene.enabled, indent: false, enabled: true),
            sectionRow(L.optionsSection),
            row(L.optionNoLock, checked: true, indent: true, enabled: scene.enabled),
            row(L.optionLid, checked: true, indent: true, enabled: scene.enabled),
            sectionRow(L.batterySection),
            row(L.batteryLid, checked: scene.batteryLid, indent: true, enabled: batteryUsable),
            row("\(L.batteryFloorMenu)  20%", checked: false, indent: true, enabled: batterySubUsable, submenu: true),
            row(L.batteryTimerMenu, checked: false, indent: true, enabled: batterySubUsable, submenu: true),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        return stack
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
