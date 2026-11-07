import SwiftUI

/// Settings of the glowing outline drawn around the notch while audio plays, with a live preview.
struct GlowSettingsSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section {
            Toggle(L("glow.enabled"), isOn: $settings.audioGlow)
            if settings.audioGlow {
                preview
                Picker(L("glow.style"), selection: $settings.glowStyle) {
                    Text(L("glow.style.diffuse")).tag(GlowStyle.diffuse)
                    Text(L("glow.style.line")).tag(GlowStyle.line)
                }
                .pickerStyle(.segmented)
                slider(settings.glowStyle == .diffuse ? "glow.spread" : "glow.width", value: $settings.glowWidth,
                       range: 1...16, step: 0.5, unit: "pt")
                slider("glow.blur", value: $settings.glowBlur, range: 0...60, step: 1, unit: "pt")
                slider("glow.intensity", value: $settings.glowIntensity, range: 0.2...1, step: 0.05, percent: true)
                slider("glow.offset", value: $settings.glowOffset, range: -2...8, step: 0.5, unit: "pt")
                Toggle(L("glow.pulse"), isOn: $settings.glowPulse)
                if settings.glowPulse {
                    slider("glow.pulseSpeed", value: $settings.glowPulseSpeed, range: 0.6...4, step: 0.1, unit: "s")
                }
                Picker(L("glow.color"), selection: $settings.glowUsesArtworkColor) {
                    Text(L("glow.color.artwork")).tag(true)
                    Text(L("glow.color.custom")).tag(false)
                }
                .pickerStyle(.segmented)
                if !settings.glowUsesArtworkColor {
                    ColorPicker(L("glow.color.pick"), selection: Binding(
                        get: { Color(hex: settings.glowColorHex) ?? .purple },
                        set: { settings.glowColorHex = $0.hex }
                    ), supportsOpacity: false)
                }
                Toggle(L("glow.whenPaused"), isOn: $settings.glowWhenPaused)
                HStack {
                    Spacer()
                    Button(L("settings.size.reset")) { withAnimation { settings.resetGlow() } }
                }
            }
        } header: {
            Text(L("glow.title"))
        } footer: {
            Text(L("glow.hint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A closed notch on a wallpaper-like background, glowing with the current settings.
    private var preview: some View {
        let shape = NotchShape(topRadius: 6, bottomRadius: 11)
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.25, green: 0.2, blue: 0.45), Color(red: 0.55, green: 0.3, blue: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(Color.black.opacity(0.35)).frame(height: 32)
            ZStack {
                if settings.glowStyle == .diffuse {
                    AudioGlow(shape: shape, color: Color(red: 1, green: 0.45, blue: 0.45))
                }
                shape.fill(Color.black)
                HStack {
                    RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom))
                        .frame(width: 20, height: 20)
                    Spacer()
                    AudioVisualizer(color: Color(red: 1, green: 0.55, blue: 0.4), playing: true)
                }
                .padding(.horizontal, 12)
            }
            .frame(width: 250, height: 32)
            .overlay {
                if settings.glowStyle == .line {
                    AudioGlow(shape: shape, color: Color(red: 1, green: 0.45, blue: 0.45))
                }
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.vertical, 4)
    }

    private func slider(_ key: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                        unit: String = "", percent: Bool = false) -> some View {
        LabeledContent(L(key)) {
            Slider(value: value, in: range, step: step) { EmptyView() }.frame(width: 200)
            Text(percent ? "\(Int((value.wrappedValue * 100).rounded())) %" : String(format: "%g %@", value.wrappedValue, unit))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
        }
    }
}
