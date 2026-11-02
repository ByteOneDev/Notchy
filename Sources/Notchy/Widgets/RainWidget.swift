import SwiftUI

/// Rain over the next three hours: a sentence and a bar per quarter hour.
struct RainWidget: View {
    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(widget: .rain)
            Text(summary)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            chart
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var chart: some View {
        VStack(spacing: 4) {
            // The bars take all the height left under the sentence.
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(weather.rainSlots) { slot in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(slot.isWet ? Color.cyan : Color.white.opacity(0.2))
                                .frame(height: max(3, min(1, slot.amount / 2) * geo.size.height))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: geo.size.height, alignment: .bottom)
            }
            HStack {
                Text(L("rain.axis.now"))
                Spacer()
                Text("+1 h")
                Spacer()
                Text("+2 h")
                Spacer()
                Text("+3 h")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
        }
        .animation(.easeOut, value: weather.rainSlots)
    }

    private var summary: String {
        let slots = weather.rainSlots
        guard !slots.isEmpty else { return L("rain.unavailable") }
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Loc.locale)
        if slots[0].isWet {
            guard let dry = slots.first(where: { !$0.isWet }) else { return L("rain.allAlong") }
            return L("rain.until", dry.date.formatted(time))
        }
        guard let wet = slots.first(where: \.isWet) else { return L("rain.none") }
        let minutes = max(0, Int(wet.date.timeIntervalSinceNow / 60))
        return L("rain.at", wet.date.formatted(time), minutes)
    }
}
