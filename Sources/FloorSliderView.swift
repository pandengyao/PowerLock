import Cocoa

/// 电量下限子菜单里的滑块：直接在菜单里拖动选值，不弹窗。
/// 每格 5%，范围和后台助手一致（5～90）。拖动时只更新右边的数字，松手才保存，
/// 免得拖动过程中每一格都写一次配置。
final class FloorSliderView: NSView {
    private let slider = NSSlider()
    private let value = NSTextField(labelWithString: "")
    private let onCommit: (Int) -> Void

    static let width: CGFloat = 220
    static let step = 5

    init(current: Int, onCommit: @escaping (Int) -> Void) {
        self.onCommit = onCommit
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 30))

        let range = PowerLockConfig.batteryFloorRange
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
        slider.numberOfTickMarks = (range.upperBound - range.lowerBound) / Self.step + 1
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(changed(_:))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setAccessibilityLabel(L.batteryFloorSliderLabel)

        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        value.alignment = .right
        value.translatesAutoresizingMaskIntoConstraints = false

        addSubview(slider)
        addSubview(value)
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            value.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 10),
            value.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            value.centerYAnchor.constraint(equalTo: centerYAnchor),
            value.widthAnchor.constraint(equalToConstant: 40),
        ])

        // 不在 5% 刻度上的旧值（比如手改配置写了 22）显示到最近的刻度，没动滑块就不改配置
        slider.integerValue = Self.snap(current)
        value.stringValue = "\(current)%"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func snap(_ pct: Int) -> Int {
        let range = PowerLockConfig.batteryFloorRange
        let snapped = Int((Double(pct) / Double(step)).rounded()) * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    @objc private func changed(_ sender: NSSlider) {
        let pct = Self.snap(sender.integerValue)
        value.stringValue = "\(pct)%"
        // 菜单里的滑块收不到普通的 mouseUp，用当前事件判断是否已经松手
        let type = NSApp.currentEvent?.type
        if type == .leftMouseUp || type == nil || type == .keyDown {
            onCommit(pct)
        }
    }
}
