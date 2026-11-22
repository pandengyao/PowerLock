import Cocoa

/// 菜单顶部的状态区：彩色状态点 + 标题 + 一行说明 + 当前电源。
/// 用自定义 view 是因为 NSMenuItem.subtitle 要 macOS 14.4，PowerLock 最低支持 13。
final class MenuHeaderView: NSView {
    enum Tone {
        case active, paused, off, attention

        var color: NSColor {
            switch self {
            case .active: return .systemGreen
            case .paused: return .systemOrange
            case .off: return .tertiaryLabelColor
            case .attention: return .systemRed
            }
        }
    }

    private let dot = NSView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let power = NSTextField(labelWithString: "")
    private let powerIcon = NSImageView()

    static let width: CGFloat = 300

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 74))

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4.5
        dot.translatesAutoresizingMaskIntoConstraints = false

        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail

        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.preferredMaxLayoutWidth = Self.width - 50

        power.font = .systemFont(ofSize: 11)
        power.textColor = .tertiaryLabelColor
        powerIcon.contentTintColor = .tertiaryLabelColor
        powerIcon.symbolConfiguration = .init(pointSize: 10, weight: .medium)

        let powerRow = NSStackView(views: [powerIcon, power])
        powerRow.spacing = 4

        let text = NSStackView(views: [title, detail, powerRow])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.setCustomSpacing(6, after: detail)
        text.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot)
        addSubview(text)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 9),
            dot.heightAnchor.constraint(equalToConstant: 9),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            dot.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 9),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            widthAnchor.constraint(equalToConstant: Self.width),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(tone: Tone, title: String, detail: String, onAC: Bool) {
        currentTone = tone
        applyDotColor()
        self.title.stringValue = title
        self.detail.stringValue = detail
        power.stringValue = onAC ? L.powerAC : L.powerBattery
        powerIcon.image = symbol(onAC ? "powerplug.fill" : "battery.75")
        // VoiceOver 把整块读成一句话，里面的文本框不再单独暴露
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(title). \(detail). \(power.stringValue)")
        for field in [self.title, self.detail, power] { field.setAccessibilityElement(false) }
        powerIcon.setAccessibilityElement(false)
        frame.size = fittingSize
    }

    private var currentTone: Tone?

    // layer 颜色是 CGColor，不会跟着深浅色自动变；外观变化后按当前外观重新取一次。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDotColor()
    }

    private func applyDotColor() {
        guard let tone = currentTone else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.layer?.backgroundColor = tone.color.cgColor
        }
    }
}
