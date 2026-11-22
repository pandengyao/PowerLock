import Cocoa

/// 菜单栏图标：自己画的模板图（跟随菜单栏深浅色），和 App 图标是同一个锁的造型。
///
/// - active：插电生效中，打开的锁 + 实心闪电
/// - paused：已开启但在用电池，打开的锁，锁体镂空、无闪电
/// - off：已关闭，合上的锁
/// - attention：后台助手未安装或需要更新，打开的锁 + 右上角小圆点
enum StatusIcon {
    enum State {
        case active, paused, off, attention
    }

    static func image(_ state: State) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            draw(state)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PowerLock"
        return image
    }

    /// 坐标是 18×18、从上往下。
    private static func draw(_ state: State) {
        NSColor.black.setFill()
        NSColor.black.setStroke()

        let body = NSRect(x: 3.5, y: 8.5, width: 11, height: 8)
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: 2.2, yRadius: 2.2)

        // 锁梁
        let shackle = NSBezierPath()
        shackle.lineWidth = 1.8
        shackle.lineCapStyle = .round
        let r: CGFloat = 3.3
        let cx: CGFloat = 9
        if state == .off {
            // 合上：两条腿都插进锁体
            shackle.move(to: NSPoint(x: cx - r, y: body.minY + 0.5))
            shackle.line(to: NSPoint(x: cx - r, y: 5.6))
            shackle.appendArc(withCenter: NSPoint(x: cx, y: 5.6), radius: r,
                              startAngle: 180, endAngle: 0, clockwise: false)
            shackle.line(to: NSPoint(x: cx + r, y: body.minY + 0.5))
        } else {
            // 打开：整体抬起，右腿离开锁体
            shackle.move(to: NSPoint(x: cx - r, y: body.minY + 0.5))
            shackle.line(to: NSPoint(x: cx - r, y: 4.6))
            shackle.appendArc(withCenter: NSPoint(x: cx, y: 4.6), radius: r,
                              startAngle: 180, endAngle: 0, clockwise: false)
            shackle.line(to: NSPoint(x: cx + r, y: 5.4))
        }
        shackle.stroke()

        switch state {
        case .paused:
            // 锁体只画轮廓，表示「待机」
            let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.75, dy: 0.75), xRadius: 1.6, yRadius: 1.6)
            outline.lineWidth = 1.5
            outline.stroke()
        default:
            bodyPath.fill()
        }

        if state == .active {
            // 在锁体上挖出闪电
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let my = body.midY
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: cx + 1.1, y: my - 3.4))
            bolt.line(to: NSPoint(x: cx - 2.5, y: my + 0.6))
            bolt.line(to: NSPoint(x: cx - 0.2, y: my + 0.6))
            bolt.line(to: NSPoint(x: cx - 1.1, y: my + 3.4))
            bolt.line(to: NSPoint(x: cx + 2.5, y: my - 0.6))
            bolt.line(to: NSPoint(x: cx + 0.2, y: my - 0.6))
            bolt.close()
            bolt.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }

        if state == .attention {
            // 右上角提示点，先挖一圈空隙再画实心点，在锁梁旁边也看得清
            let dot = NSRect(x: 12.6, y: 0.6, width: 4.8, height: 4.8)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: dot).fill()
        }
    }
}
