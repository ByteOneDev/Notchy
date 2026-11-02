import SwiftUI

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
                glass
                shape.fill(Color.black.opacity(isOpen ? 0.12 : 1))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isOpen)
    }

    @ViewBuilder private var glass: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.25)), in: shape)
        } else {
            VisualEffectBlur(material: .underWindowBackground)
                .clipShape(shape)
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
