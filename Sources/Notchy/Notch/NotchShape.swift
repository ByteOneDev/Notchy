import SwiftUI

/// The inner edge of the notch only (sides and bottom), without the part along the top of the
/// screen: what faces the desktop. Used for the glow while audio plays.
struct NotchOutline: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, rect.height - t)
        var p = Path()
        // Starts where the left flare meets the side, ends where the right one does.
        p.move(to: CGPoint(x: rect.minX + t, y: rect.minY + t))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        return p
    }
}

/// The notch silhouette: flared top corners that melt into the menu bar and rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, rect.height - t)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Fills the notch according to the chosen style. Closed, it stays pitch black so it blends
/// with the hardware notch; open, it takes the black / translucent / glass style.
struct NotchBackground: View {
    let appearance: NotchAppearance
    let isOpen: Bool
    let shape: NotchShape

    var body: some View {
        ZStack {
            switch appearance {
            case .black:
                shape.fill(Color.black)
            case .translucent:
                VisualEffectBlur(material: .hudWindow)
                    .clipShape(shape)
                shape.fill(Color.black.opacity(isOpen ? 0.55 : 1))
            case .glass:
                glass(tint: 0.25)
                shape.fill(Color.black.opacity(isOpen ? 0.12 : 1))
            case .liquidGlass:
                // Smoky glass with a lit rim, like NotchNook Pro.
                glass(tint: 0.5)
                shape.fill(Color.black.opacity(isOpen ? 0.28 : 1))
                if isOpen {
                    shape.stroke(LiquidGlassRim.gradient, lineWidth: 1)
                    shape.fill(RadialGradient(colors: [.white.opacity(0.07), .clear], center: .top, startRadius: 0, endRadius: 260))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isOpen)
    }

    @ViewBuilder private func glass(tint: Double) -> some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(tint)), in: shape)
        } else {
            VisualEffectBlur(material: .hudWindow)
                .clipShape(shape)
        }
    }
}

enum LiquidGlassRim {
    /// Light catching the edge: bright at the bottom corners, fading up the sides.
    static let gradient = LinearGradient(
        stops: [.init(color: .white.opacity(0.0), location: 0), .init(color: .white.opacity(0.08), location: 0.4),
                .init(color: .white.opacity(0.32), location: 1)],
        startPoint: .top, endPoint: .bottom)
}

/// Background of any floating capsule (the panel bar) in the current style.
struct CapsuleBackground: View {
    let appearance: NotchAppearance

    var body: some View {
        switch appearance {
        case .black:
            Capsule().fill(Color.black)
                .overlay(Capsule().stroke(Color.white.opacity(0.1)))
        case .translucent:
            VisualEffectBlur(material: .hudWindow).clipShape(Capsule())
                .overlay(Capsule().fill(Color.black.opacity(0.5)))
                .overlay(Capsule().stroke(Color.white.opacity(0.1)))
        case .glass, .liquidGlass:
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(.black.opacity(appearance == .liquidGlass ? 0.45 : 0.2)), in: Capsule())
                    .overlay(Capsule().stroke(LiquidGlassRim.gradient, lineWidth: 1))
            } else {
                VisualEffectBlur(material: .hudWindow).clipShape(Capsule())
                    .overlay(Capsule().fill(Color.black.opacity(0.35)))
            }
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
