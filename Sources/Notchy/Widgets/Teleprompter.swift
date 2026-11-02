import SwiftUI

/// Scrolls a script right under the camera, so you read while looking at it.
@MainActor
final class Teleprompter: ObservableObject {
    static let shared = Teleprompter()

    @Published var text: String { didSet { UserDefaults.standard.set(text, forKey: "teleprompterText") } }
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "teleprompterSpeed") } }
    @Published var fontSize: Double { didSet { UserDefaults.standard.set(fontSize, forKey: "teleprompterFontSize") } }
    @Published var isEditing = false
    @Published private(set) var isRunning = false
    @Published private(set) var countdown: Int?
    /// How far the text has scrolled, in points.
    @Published private(set) var offset: CGFloat = 0
    /// Height of the laid out text, reported by the view; scrolling stops at the end.
    var textHeight: CGFloat = 0

    /// Points per second at speed ×1.
    static let baseSpeed: Double = 28
    private var timer: Timer?
    private var lastTick = Date.now

    private init() {
        let defaults = UserDefaults.standard
        text = defaults.string(forKey: "teleprompterText") ?? ""
        speed = defaults.object(forKey: "teleprompterSpeed") as? Double ?? 1
        fontSize = defaults.object(forKey: "teleprompterFontSize") as? Double ?? 22
    }

    var isFinished: Bool { textHeight > 0 && offset >= textHeight }

    var remainingTime: TimeInterval {
        max(0, Double(textHeight - offset) / (Self.baseSpeed * speed))
    }

    func toggle() {
        if isRunning || countdown != nil { pause() } else { start() }
    }

    /// Starts after a 3-2-1 countdown, from the beginning if the end was reached.
    func start() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { isEditing = true; return }
        isEditing = false
        if isFinished { offset = 0 }
        countdown = 3
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let count = self.countdown else { return timer.invalidate() }
                if count > 1 {
                    self.countdown = count - 1
                } else {
                    timer.invalidate()
                    self.countdown = nil
                    self.run()
                }
            }
        }
    }

    private func run() {
        isRunning = true
        lastTick = .now
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        let now = Date.now
        offset += CGFloat(now.timeIntervalSince(lastTick) * Self.baseSpeed * speed)
        lastTick = now
        if isFinished {
            offset = textHeight
            pause()
        }
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        countdown = nil
        isRunning = false
    }

    func restart() {
        offset = 0
        if isRunning { lastTick = .now }
    }

    /// Manual scroll with two fingers.
    func nudge(by delta: CGFloat) {
        offset = min(max(0, offset + delta), max(textHeight, 0))
        lastTick = .now
    }

    func changeSpeed(by delta: Double) {
        speed = min(4, max(0.25, (speed + delta) * 100).rounded() / 100)
    }

    func changeFontSize(by delta: Double) {
        fontSize = min(40, max(14, fontSize + delta))
    }
}

struct TeleprompterView: View {
    @ObservedObject private var prompter = Teleprompter.shared
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            controls
            if prompter.isEditing {
                editor
            } else {
                reader
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { prompter.toggle() } label: {
                    Image(systemName: prompter.isRunning || prompter.countdown != nil ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(CircleButtonStyle(color: .accentColor))
                Button { prompter.restart() } label: { Image(systemName: "backward.end.fill") }
                    .buttonStyle(CircleButtonStyle())
                    .help(L("teleprompter.restart"))
                Button {
                    prompter.pause()
                    prompter.isEditing.toggle()
                } label: { Image(systemName: prompter.isEditing ? "checkmark" : "pencil") }
                    .buttonStyle(CircleButtonStyle())
                    .help(prompter.isEditing ? L("teleprompter.done") : L("teleprompter.edit"))
            }
            Stepper(value: Binding(get: { prompter.speed }, set: { prompter.speed = $0 }), in: 0.25...4, step: 0.25) {
                Label(String(format: "×%.2g", prompter.speed), systemImage: "gauge.with.dots.needle.33percent")
            }
            Stepper(value: Binding(get: { prompter.fontSize }, set: { prompter.fontSize = $0 }), in: 14...40, step: 2) {
                Label("\(Int(prompter.fontSize)) pt", systemImage: "textformat.size")
            }
            Text(L("teleprompter.remaining", prompter.remainingTime.clock))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
        .font(.system(size: 11, weight: .medium))
        .controlSize(.mini)
        .frame(width: 128, alignment: .leading)
    }

    private var editor: some View {
        TextEditor(text: $prompter.text)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(alignment: .topLeading) {
                if prompter.text.isEmpty {
                    Text(L("teleprompter.placeholder"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .focused($editorFocused)
            .onAppear {
                NSApp.activate()
                editorFocused = true
            }
    }

    private var reader: some View {
        GeometryReader { geo in
            // The line being read sits in the upper third, closest to the camera.
            let readingLine = geo.size.height * 0.3
            ZStack(alignment: .top) {
                if prompter.text.isEmpty {
                    Button(L("teleprompter.empty")) { prompter.isEditing = true }
                        .buttonStyle(PillButtonStyle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(prompter.text)
                        .font(.system(size: prompter.fontSize, weight: .semibold))
                        .lineSpacing(prompter.fontSize * 0.25)
                        .multilineTextAlignment(.center)
                        .frame(width: geo.size.width)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { prompter.textHeight = $0 }
                        .offset(y: readingLine - prompter.offset)
                }
                if let count = prompter.countdown {
                    Text("\(count)")
                        .font(.system(size: 54, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText(countsDown: true))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.6))
                        .animation(.snappy, value: count)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .topLeading) {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .offset(x: -10, y: readingLine + prompter.fontSize * 0.45)
            }
        }
    }
}
