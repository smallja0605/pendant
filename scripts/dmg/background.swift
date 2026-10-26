// Draws the installer window's background (theme: a pendant hanging from the notch in a night sky).
// Usage: swift scripts/dmg/background.swift <output-folder>   writes background.png (660 x 400) and background@2x.png
import AppKit

let width = 660.0, height = 400.0

func render(scale: Double, to url: URL) {
    let pixelsWide = Int(width * scale), pixelsHigh = Int(height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no bitmap") }
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: scale, y: scale)
    // Work top-down like the window: y = 0 at the top edge.
    cg.translateBy(x: 0, y: height)
    cg.scaleBy(x: 1, y: -1)
    let space = CGColorSpaceCreateDeviceRGB()

    // Night sky: the same blue to violet as the settings' demo desktop, darker towards the bottom.
    let sky = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.10, green: 0.14, blue: 0.34, alpha: 1), CGColor(red: 0.26, green: 0.16, blue: 0.42, alpha: 1),
        CGColor(red: 0.07, green: 0.07, blue: 0.16, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    cg.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: width * 0.25, y: height * 1.1),
                          options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Stars: a fixed pseudo-random scatter so every build looks the same.
    var seed: UInt64 = 20_261_027
    func next() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 33) / Double(1 << 31)
    }
    for _ in 0..<70 {
        let x = next() * width, y = next() * height * 0.7, radius = 0.4 + next() * 1.1
        cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.2 + next() * 0.5))
        cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    // The notch at the top edge, the thread and the pendant.
    let centerX = width / 2
    cg.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    let notch = CGPath(roundedRect: CGRect(x: centerX - 62, y: -20, width: 124, height: 46), cornerWidth: 18, cornerHeight: 18, transform: nil)
    cg.addPath(notch)
    cg.fillPath()
    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    cg.setLineWidth(1)
    cg.move(to: CGPoint(x: centerX, y: 26))
    cg.addLine(to: CGPoint(x: centerX, y: 84))
    cg.strokePath()
    let glow = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1, green: 0.78, blue: 0.45, alpha: 0.75), CGColor(red: 1, green: 0.55, blue: 0.35, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: centerX, y: 96), startRadius: 0, endCenter: CGPoint(x: centerX, y: 96), endRadius: 34, options: [])
    let drop = CGMutablePath()
    drop.move(to: CGPoint(x: centerX, y: 82))
    drop.addCurve(to: CGPoint(x: centerX, y: 112), control1: CGPoint(x: centerX + 12, y: 94), control2: CGPoint(x: centerX + 11, y: 112))
    drop.addCurve(to: CGPoint(x: centerX, y: 82), control1: CGPoint(x: centerX - 11, y: 112), control2: CGPoint(x: centerX - 12, y: 94))
    cg.addPath(drop)
    cg.setFillColor(CGColor(red: 1, green: 0.86, blue: 0.62, alpha: 1))
    cg.fillPath()

    // A dotted arrow between the two icons.
    let iconY = 232.0
    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
    cg.setLineWidth(2.5)
    cg.setLineCap(.round)
    cg.setLineDash(phase: 0, lengths: [0.1, 9])
    cg.move(to: CGPoint(x: 252, y: iconY))
    cg.addLine(to: CGPoint(x: 394, y: iconY))
    cg.strokePath()
    cg.setLineDash(phase: 0, lengths: [])
    cg.setLineWidth(3)
    cg.setLineJoin(.round)
    cg.move(to: CGPoint(x: 398, y: iconY - 10))
    cg.addLine(to: CGPoint(x: 410, y: iconY))
    cg.addLine(to: CGPoint(x: 398, y: iconY + 10))
    cg.strokePath()

    // The caption (drawn upright: undo the flip for text).
    cg.saveGState()
    cg.translateBy(x: 0, y: height)
    cg.scaleBy(x: 1, y: -1)
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let caption = NSAttributedString(string: "將 Pendant 拖曳到「應用程式」", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.85), .paragraphStyle: style,
    ])
    caption.draw(in: CGRect(x: 0, y: 40, width: width, height: 24))
    cg.restoreGState()

    NSGraphicsContext.current = nil
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try! data.write(to: url)
}

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
render(scale: 1, to: folder.appendingPathComponent("background.png"))
render(scale: 2, to: folder.appendingPathComponent("background@2x.png"))
