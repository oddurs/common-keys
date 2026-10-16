// Renders Resources/AppIcon.icns and docs/icon.png. Run: swift scripts/make-icon.swift
import AppKit

func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's icon grid: an 824 pt body centred on a 1024 pt canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.set()
    NSGradient(colors: [color(0x3a8dff), color(0x0062d6)])!.draw(in: shape, angle: -90)
    NSShadow().set()

    // A key cap with a Latin and a Cyrillic letter: one key, two keyboards.
    let cap = NSRect(x: 250, y: 269, width: 524, height: 487)
    color(0xffffff, alpha: 0.96).setFill()
    NSBezierPath(roundedRect: cap, xRadius: 112, yRadius: 112).fill()
    let font = NSFont.systemFont(ofSize: 253, weight: .semibold)
    for (letter, centre, ink) in [("A", 409.0, color(0x1d1d1f)), ("Ж", 624.0, color(0x0062d6))] {
        let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: ink])
        let baseline: CGFloat = 428
        text.draw(at: NSPoint(x: centre - text.size().width / 2, y: baseline + font.descender))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
if FileManager.default.fileExists(atPath: iconset.path) { try FileManager.default.removeItem(at: iconset) }
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(256).write(to: root.appendingPathComponent("docs/icon.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
