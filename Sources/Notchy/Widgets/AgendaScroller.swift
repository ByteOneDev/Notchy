import SwiftUI

/// A list that the notch scrolls itself (see `CalendarService.agendaOffset`), faded at the
/// edges where more is hidden.
struct AgendaScroller<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ObservedObject private var service = CalendarService.shared
    @State private var contentHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0

    var body: some View {
        let maxOffset = max(0, contentHeight - containerHeight)
        let offset = min(service.agendaOffset, maxOffset)
        GeometryReader { geo in
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: geo.size.width, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    contentHeight = $0
                    publish()
                }
                .offset(y: -offset)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            containerHeight = $0
            publish()
        }
        .clipped()
        .mask(
            LinearGradient(stops: [
                .init(color: offset > 1 ? .clear : .black, location: 0),
                .init(color: .black, location: offset > 1 ? 0.12 : 0),
                .init(color: .black, location: offset < maxOffset - 1 ? 0.82 : 1),
                .init(color: offset < maxOffset - 1 ? .clear : .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        .contentShape(Rectangle())
        .onHover { service.agendaHovered = $0 }
        .onDisappear { service.agendaHovered = false }
    }

    private func publish() {
        service.agendaMaxOffset = max(0, contentHeight - containerHeight)
    }
}
