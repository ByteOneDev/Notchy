import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject private var store = ShelfStore.shared
    @State private var shelfTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            shelf
            DropTile(icon: "dot.radiowaves.up.forward", title: L("shelf.airdrop"), color: .blue) { urls in
                store.airDrop(urls)
            }
            ConvertTile()
        }
    }

    private var shelf: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(shelfTargeted ? 0.6 : 0.15), style: StrokeStyle(lineWidth: 1.5, dash: store.items.isEmpty || shelfTargeted ? [6, 5] : []))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(shelfTargeted ? 0.08 : 0.04)))
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                    Text(L("shelf.empty")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.items) { ShelfItemView(item: $0) }
                    }
                    .padding(.horizontal, 10)
                }
                .overlay(alignment: .topTrailing) {
                    Button { withAnimation { store.clear() } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help(L("shelf.clear"))
                    .padding(8)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $shelfTargeted) { providers in
            store.add(providers: providers)
            return true
        }
        .animation(.snappy, value: store.items)
    }
}

private struct ShelfItemView: View {
    let item: ShelfStore.Item
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon).resizable().frame(width: 52, height: 52)
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.1 : 0)))
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button(L("shelf.open")) { NSWorkspace.shared.open(item.url) }
            Button(L("shelf.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button(L("shelf.airdrop")) { ShelfStore.shared.airDrop([item.url]) }
            let formats = FileConverter.formats(for: [item.url])
            if !formats.isEmpty {
                Menu(L("shelf.convert")) {
                    ForEach(formats) { format in
                        Button(format.label) { FileConverter.convert([item.url], to: format) }
                    }
                }
            }
            Divider()
            Button(L("shelf.remove")) { ShelfStore.shared.remove(item) }
        }
    }
}

/// A square target files can be dropped on.
private struct DropTile: View {
    let icon: String
    let title: String
    let color: Color
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(color)
                .symbolEffect(.bounce, value: targeted)
            Text(title).font(.system(size: 11, weight: .medium))
        }
        .frame(width: 104)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.opacity(targeted ? 0.3 : 0.12)))
        .scaleEffect(targeted ? 1.04 : 1)
        .animation(.spring(response: 0.3), value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            ShelfStore.loadURLs(from: providers, completion: onDrop)
            return true
        }
        .onTapGesture {
            // Clicking sends what is on the shelf.
            onDrop(ShelfStore.shared.items.map(\.url))
        }
    }
}

private struct ConvertTile: View {
    @ObservedObject private var store = ShelfStore.shared
    @State private var targeted = false

    var body: some View {
        Group {
            if store.pendingConversion.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 22, weight: .semibold)).foregroundStyle(.purple)
                        .symbolEffect(.rotate, value: targeted)
                    Text(L("shelf.convert")).font(.system(size: 11, weight: .medium))
                }
            } else {
                formatPicker
            }
        }
        .frame(width: 104)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.purple.opacity(targeted ? 0.3 : 0.12)))
        .animation(.spring(response: 0.3), value: targeted)
        .animation(.snappy, value: store.pendingConversion)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            ShelfStore.loadURLs(from: providers) { urls in store.pendingConversion = urls }
            return true
        }
    }

    @ViewBuilder private var formatPicker: some View {
        let formats = FileConverter.formats(for: store.pendingConversion)
        VStack(spacing: 4) {
            if formats.isEmpty {
                Text(L("convert.unsupported")).font(.system(size: 10)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.6))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                    ForEach(formats) { format in
                        Button(format.label) {
                            FileConverter.convert(store.pendingConversion, to: format)
                            store.pendingConversion = []
                        }
                        .buttonStyle(PillButtonStyle(color: .purple))
                    }
                }
            }
            Button(L("common.cancel")) { store.pendingConversion = [] }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(8)
    }
}
