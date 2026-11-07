import SwiftUI

/// The modes with a switch each: turn one on or off by hand, whatever its trigger.
struct ModesWidget: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engine = ModeEngine.shared

    private var modes: [ModeRule] { settings.modes.filter(\.enabled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .modes) {
                if modes.count > 4 {
                    Text(L("calendar.more", modes.count - 4)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
            }
            if modes.isEmpty {
                Spacer(minLength: 0)
                Button(L("modes.add")) { SettingsWindowController.shared.show(pane: .modes) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(modes.prefix(4)) { mode in row(mode) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ mode: ModeRule) -> some View {
        let on = engine.active.contains(mode.id)
        let blocked = mode.allBlockedSites.count
        return Button { withAnimation(.snappy) { engine.toggle(mode) } } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? .white : .purple)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(on ? Color.purple : Color.purple.opacity(0.18)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(mode.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(on ? (blocked > 0 ? L("modes.widget.blocking", blocked) : L("modes.active")) : mode.trigger.title)
                        .font(.system(size: 10)).foregroundStyle(on ? .purple : .white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 4)
                // A small switch, like iOS.
                Capsule()
                    .fill(on ? Color.purple : Color.white.opacity(0.18))
                    .frame(width: 30, height: 18)
                    .overlay(alignment: on ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
