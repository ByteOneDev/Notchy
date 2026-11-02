// Renders Resources/AppIcon.icns: a dark squircle with a glowing notch.
// Usage: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.32, alpha: 1),
                        NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.06, alpha: 1)])!.draw(in: squircle, angle: -90)

    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    // Glow under the notch
    let glow = NSGradient(colors: [NSColor(calibratedRed: 0.55, green: 0.4, blue: 1, alpha: 0.55), .clear])!
    glow.draw(fromCenter: NSPoint(x: 512 * s, y: 700 * s), radius: 0, toCenter: NSPoint(x: 512 * s, y: 700 * s), radius: 330 * s, options: [])

    // The notch, hanging from the top edge
    let notch = NSBezierPath(roundedRect: NSRect(x: 262 * s, y: 690 * s, width: 500 * s, height: 260 * s), xRadius: 110 * s, yRadius: 110 * s)
    NSColor.black.setFill()
    notch.fill()
    // Artwork + visualizer inside the notch
    let art = NSBezierPath(roundedRect: NSRect(x: 322 * s, y: 742 * s, width: 92 * s, height: 92 * s), xRadius: 24 * s, yRadius: 24 * s)
    NSGradient(colors: [NSColor.systemPink, NSColor.systemOrange])!.draw(in: art, angle: -45)
    let heights: [CGFloat] = [40, 78, 56, 92]
    for (i, h) in heights.enumerated() {
        let bar = NSBezierPath(roundedRect: NSRect(x: (590 + CGFloat(i) * 32) * s, y: (788 - h / 2) * s, width: 18 * s, height: h * s), xRadius: 9 * s, yRadius: 9 * s)
        NSColor(calibratedRed: 0.75, green: 0.65, blue: 1, alpha: 1).setFill()
        bar.fill()
    }
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print("Resources/AppIcon.icns")
