// 生成 PowerLock 的 App 图标：蓝色 macOS 圆角方形底板 + 白色打开的锁 + 琥珀色闪电。
// 用法见 scripts/make_icon.sh。只依赖系统自带的 AppKit / CoreGraphics。
import AppKit

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "build/icon"
let variant = args.count > 2 ? args[2] : "amber"   // amber：琥珀色闪电；cutout：闪电镂空

let S = 1024

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

/// macOS 图标底板：824×824 的超椭圆（n≈5），和系统图标的连续圆角一致。
func squircle(_ rect: CGRect, n: CGFloat = 5.0, steps: Int = 1440) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let p = CGPoint(x: rect.midX + a * copysign(pow(abs(c), 2 / n), c),
                        y: rect.midY + b * copysign(pow(abs(s), 2 / n), s))
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
}

func linearGradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// small：给 16/32 像素用的版本，闪电更粗、锁梁更粗，缩小后不糊。
func render(small: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // 下面都用「从上往下」的坐标，方便对照设计稿。阴影偏移不受这个变换影响，仍按设备坐标（向下为负）。
    ctx.translateBy(x: 0, y: CGFloat(S))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // 底板
    let plateRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let plate = squircle(plateRect)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.30))
    ctx.addPath(plate)
    ctx.setFillColor(rgb(0x2F66EC))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    linearGradient(ctx, [rgb(0x63A2FF), rgb(0x3770F0), rgb(0x1C48D2)],
                   from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    // 顶部柔光
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 60), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 60), endRadius: 560, options: [])
    ctx.restoreGState()

    // 底板内侧的细高光边
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    ctx.addPath(plate)
    ctx.setLineWidth(6)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.16))
    ctx.strokePath()
    ctx.restoreGState()

    // 锁的几何（从上往下的坐标）
    let cx: CGFloat = 512
    let body = CGRect(x: 302, y: 478, width: 420, height: 322)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 76, cornerHeight: 76, transform: nil)
    let r: CGFloat = 134          // 锁梁中心线半径
    let w: CGFloat = small ? 92 : 74   // 锁梁粗细
    let arcY: CGFloat = 384       // 锁梁圆心，抬起表示「打开」
    let shackle = CGMutablePath()
    shackle.move(to: CGPoint(x: cx - r, y: body.minY + 40))      // 左腿插在锁体里
    shackle.addLine(to: CGPoint(x: cx - r, y: arcY))
    shackle.addArc(center: CGPoint(x: cx, y: arcY), radius: r,
                   startAngle: .pi, endAngle: 0, clockwise: false)
    shackle.addLine(to: CGPoint(x: cx + r, y: 404))              // 右腿抬起，离开锁体
    let shackleShape = shackle.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10)

    // 锁投在底板上的阴影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x0A2378, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(shackleShape)
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // 锁梁：浅银白渐变
    ctx.saveGState()
    ctx.addPath(shackleShape)
    ctx.clip()
    linearGradient(ctx, [rgb(0xFFFFFF), rgb(0xD5E1FF)], from: CGPoint(x: cx, y: 210), to: CGPoint(x: cx, y: 520))
    ctx.restoreGState()

    // 锁体：白色渐变
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    linearGradient(ctx, [rgb(0xFFFFFF), rgb(0xE6EDFF)], from: CGPoint(x: cx, y: body.minY), to: CGPoint(x: cx, y: body.maxY))
    // 锁体顶部一条浅阴影，表现锁梁和锁体的前后关系
    linearGradient(ctx, [rgb(0x1C48D2, 0.10), rgb(0x1C48D2, 0)],
                   from: CGPoint(x: cx, y: body.minY), to: CGPoint(x: cx, y: body.minY + 26))
    ctx.restoreGState()

    // 闪电
    let by = body.midY + 2
    let bolt = CGMutablePath()
    bolt.addLines(between: [
        CGPoint(x: cx + 30, y: by - 108),
        CGPoint(x: cx - 66, y: by + 14),
        CGPoint(x: cx - 6, y: by + 14),
        CGPoint(x: cx - 32, y: by + 108),
        CGPoint(x: cx + 66, y: by - 16),
        CGPoint(x: cx + 6, y: by - 16),
    ])
    bolt.closeSubpath()
    let boltShape = bolt.copy(strokingWithWidth: small ? 40 : 14, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.saveGState()
    ctx.addPath(bolt)
    ctx.addPath(boltShape)
    ctx.clip()
    if variant == "cutout" {
        linearGradient(ctx, [rgb(0x4B85F6), rgb(0x2453D8)], from: CGPoint(x: cx, y: by - 110), to: CGPoint(x: cx, y: by + 110))
    } else {
        linearGradient(ctx, [rgb(0xFFD84D), rgb(0xFFA30F)], from: CGPoint(x: cx, y: by - 110), to: CGPoint(x: cx, y: by + 110))
    }
    ctx.restoreGState()

    return ctx.makeImage()!
}

func resized(_ image: CGImage, _ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let master = render()
let smallMaster = render(small: true)
let iconset = outDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    let source = px <= 32 ? smallMaster : master
    writePNG(px == 1024 ? master : resized(source, px), "\(iconset)/\(name).png")
}
writePNG(resized(smallMaster, 32), outDir + "/icon-32-small.png")
writePNG(master, outDir + "/icon-1024.png")
print("wrote \(iconset)")
