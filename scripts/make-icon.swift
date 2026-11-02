// Renders the Notchy logo: a notch hanging from the top of a dark squircle, with light
// spilling out of it. Writes Resources/AppIcon.icns and docs/logo.png.
// Usage: swift scripts/make-icon.swift
import AppKit

/// The notch silhouette: concave top corners, rounded bottom corners (y grows upward).
func notchPath(minX: CGFloat, maxX: CGFloat, bottom: CGFloat, top: CGFloat, topRadius t: CGFloat, bottomRadius b: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: minX - t, y: top))
    p.curve(to: NSPoint(x: minX, y: top - t), controlPoint1: NSPoint(x: minX - t * 0.45, y: top), controlPoint2: NSPoint(x: minX, y: top - t * 0.45))
    p.line(to: NSPoint(x: minX, y: bottom + b))
    p.curve(to: NSPoint(x: minX + b, y: bottom), controlPoint1: NSPoint(x: minX, y: bottom + b * 0.45), controlPoint2: NSPoint(x: minX + b * 0.45, y: bottom))
    p.line(to: NSPoint(x: maxX - b, y: bottom))
    p.curve(to: NSPoint(x: maxX, y: bottom + b), controlPoint1: NSPoint(x: maxX - b * 0.45, y: bottom), controlPoint2: NSPoint(x: maxX, y: bottom + b * 0.45))
    p.line(to: NSPoint(x: maxX, y: top - t))
    p.curve(to: NSPoint(x: maxX + t, y: top), controlPoint1: NSPoint(x: maxX, y: top - t * 0.45), controlPoint2: NSPoint(x: maxX + t * 0.45, y: top))
    p.close()
    return p
}

func glow(_ color: NSColor, at center: NSPoint, radius: CGFloat) {
    NSGradient(colors: [color, color.withAlphaComponent(0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = size / 1024
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }

    // Body: the standard macOS icon grid (824 pt squircle inside 1024).
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186 * s, yRadius: 186 * s)
    NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.08, blue: 0.20, alpha: 1),
                        NSColor(srgbRed: 0.02, green: 0.02, blue: 0.04, alpha: 1)])!.draw(in: squircle, angle: -90)

    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()

    // Light spilling out of the notch.
    glow(NSColor(srgbRed: 0.55, green: 0.36, blue: 1.0, alpha: 0.85), at: pt(512, 640), radius: 430 * s)
    glow(NSColor(srgbRed: 1.0, green: 0.36, blue: 0.62, alpha: 0.55), at: pt(380, 610), radius: 280 * s)
    glow(NSColor(srgbRed: 0.25, green: 0.80, blue: 1.0, alpha: 0.50), at: pt(650, 600), radius: 280 * s)
    // Soft floor so the bottom stays dark and deep.
    NSGradient(colors: [NSColor(srgbRed: 0.02, green: 0.02, blue: 0.04, alpha: 0.9), .clear])!
        .draw(in: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 360 * s), angle: 90)

    // The notch.
    let notch = notchPath(minX: 300 * s, maxX: 724 * s, bottom: 650 * s, top: 924 * s, topRadius: 46 * s, bottomRadius: 96 * s)
    NSColor.black.setFill()
    notch.fill()
    // Rim light along the notch edge.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.75, green: 0.62, blue: 1, alpha: 0.9)
    shadow.shadowBlurRadius = 28 * s
    shadow.set()
    NSColor(srgbRed: 0.85, green: 0.78, blue: 1, alpha: 0.55).setStroke()
    notch.lineWidth = 5 * s
    notch.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSColor.black.setFill()
    notch.fill()

    // Camera dot.
    let lens = NSBezierPath(ovalIn: NSRect(x: 492 * s, y: 806 * s, width: 40 * s, height: 40 * s))
    NSColor(srgbRed: 0.10, green: 0.10, blue: 0.16, alpha: 1).setFill()
    lens.fill()
    let glint = NSBezierPath(ovalIn: NSRect(x: 503 * s, y: 822 * s, width: 12 * s, height: 12 * s))
    NSColor(srgbRed: 0.45, green: 0.45, blue: 0.75, alpha: 0.8).setFill()
    glint.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Hairline border.
    NSColor(white: 1, alpha: 0.08).setStroke()
    squircle.lineWidth = 3 * s
    squircle.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try! FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
try! render(size: 512).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("docs/logo.png"))
print("Resources/AppIcon.icns, docs/logo.png")
