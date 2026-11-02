import AVFoundation
import Speech
import SwiftUI

/// Scrolls a script right under the camera, so you read while looking at it. Either at a fixed
/// speed, or following your voice with on-device speech recognition.
@MainActor
final class Teleprompter: ObservableObject {
    static let shared = Teleprompter()

    @Published var text: String {
        didSet {
            UserDefaults.standard.set(text, forKey: "teleprompterText")
            voice.setScript(text)
        }
    }
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "teleprompterSpeed") } }
    @Published var fontSize: Double { didSet { UserDefaults.standard.set(fontSize, forKey: "teleprompterFontSize") } }
    @Published var isEditing = false
    @Published private(set) var isRunning = false
    @Published private(set) var countdown: Int?
    /// How far the text has scrolled, in points.
    @Published private(set) var offset: CGFloat = 0
    /// Height of the laid out text, reported by the view; scrolling stops at the end.
    var textHeight: CGFloat = 0
    /// Vertical position of a character in the laid out text, provided by the text view.
    var yForCharacter: ((Int) -> CGFloat)?

    let voice = VoiceFollower()

    /// Points per second at speed ×1.
    static let baseSpeed: Double = 28
    private var timer: Timer?
    private var lastTick = Date.now

    private init() {
        let defaults = UserDefaults.standard
        text = defaults.string(forKey: "teleprompterText") ?? ""
        speed = defaults.object(forKey: "teleprompterSpeed") as? Double ?? 1
        fontSize = defaults.object(forKey: "teleprompterFontSize") as? Double ?? 22
        voice.setScript(text)
    }

    var followsVoice: Bool { AppSettings.shared.teleprompterFollowsVoice }
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
        if isFinished { restart() }
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
        if followsVoice { voice.start() }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        let now = Date.now
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        if followsVoice {
            // Glide toward the line being spoken.
            guard let location = voice.spokenLocation, let y = yForCharacter?(location) else { return }
            offset += (y - offset) * CGFloat(min(1, dt * 5))
        } else {
            offset += CGFloat(dt * Self.baseSpeed * speed)
            if isFinished {
                offset = textHeight
                pause()
            }
        }
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        countdown = nil
        isRunning = false
        voice.stop()
    }

    func restart() {
        offset = 0
        voice.reset()
        if isRunning { lastTick = .now }
    }

    /// Manual scroll with two fingers.
    func nudge(by delta: CGFloat) {
        offset = min(max(0, offset + delta), max(textHeight, 0))
        lastTick = .now
    }
}

/// Follows the reader through the script with on-device speech recognition.
@MainActor
final class VoiceFollower: ObservableObject {
    private struct Word {
        let text: String
        let location: Int
    }

    /// Index of the next word to be read.
    @Published private(set) var cursor = 0
    @Published private(set) var isListening = false
    @Published private(set) var error: String?

    private var words: [Word] = []
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    /// Words of the current recognition task already matched.
    private var consumedWords = 0

    /// Location (UTF-16 offset) of the next word to read, for scrolling and highlighting.
    var spokenLocation: Int? {
        guard !words.isEmpty else { return nil }
        return words[min(cursor, words.count - 1)].location
    }

    func setScript(_ script: String) {
        var result: [Word] = []
        let ns = script as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { word, range, _, _ in
            if let word { result.append(Word(text: Self.normalize(word), location: range.location)) }
        }
        words = result
        cursor = min(cursor, max(0, result.count - 1))
    }

    func reset() { cursor = 0 }

    func start() {
        guard !isListening else { return }
        error = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard status == .authorized else { self.error = L("voice.denied"); return }
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                if granted { self.beginRecognition() } else { self.error = L("voice.micDenied") }
                            }
                        }
                    }
                }
            }
        }
    }

    func stop() {
        isListening = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        PrivacyMonitor.shared.ignoreMicrophone = false
    }

    private func beginRecognition() {
        let locale = Locale(identifier: AppSettings.shared.teleprompterLanguage == .fr ? "fr-FR" : "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            error = L("voice.unavailable")
            return
        }
        self.recognizer = recognizer
        PrivacyMonitor.shared.ignoreMicrophone = true
        isListening = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Audio thread: hand the buffer to the current request.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.request?.append(buffer) } }
        }
        engine.prepare()
        do { try engine.start() } catch {
            self.error = L("voice.micDenied")
            stop()
            return
        }
        startTask()
    }

    /// One recognition task; restarted whenever it ends so listening is continuous.
    private func startTask() {
        guard isListening, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.taskHint = .dictation
        self.request = request
        consumedWords = 0
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let spoken = result?.bestTranscription.segments.map(\.substring) ?? []
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if !spoken.isEmpty { self.follow(spoken) }
                    if isFinal || error != nil {
                        self.request?.endAudio()
                        self.task = nil
                        if self.isListening { self.startTask() }
                    }
                }
            }
        }
    }

    /// Moves the cursor to where the last spoken words appear, just ahead in the script.
    private func follow(_ spoken: [String]) {
        let fresh = spoken.map(Self.normalize).filter { !$0.isEmpty }
        guard fresh.count > consumedWords, !words.isEmpty else { return }
        let recent = Array(fresh.suffix(min(4, fresh.count)))
        let window = max(0, cursor - 2)..<min(words.count, cursor + 30)
        var best: (index: Int, score: Int)?
        for end in window {
            // Count how many of the recent words line up, ending at `end`.
            var score = 0
            for (offset, word) in recent.reversed().enumerated() {
                let index = end - offset
                guard index >= 0 else { break }
                if Self.similar(words[index].text, word) { score += 1 }
            }
            // Prefer the closest match; long single words are enough to resync.
            let enough = score >= 2 || (score == 1 && recent.count == 1 && words[end].text.count >= 4 && end - cursor <= 3)
            if enough, score > (best?.score ?? 0) { best = (end, score) }
        }
        if let best, best.index + 1 > cursor {
            cursor = min(best.index + 1, words.count - 1)
            consumedWords = fresh.count
        }
    }

    private static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // Tolerate small recognition slips on longer words (plural, elision…).
        guard a.count >= 4, b.count >= 4 else { return false }
        return a.hasPrefix(String(b.prefix(4))) && abs(a.count - b.count) <= 2
    }

    private static func normalize(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Views

struct TeleprompterView: View {
    @ObservedObject private var prompter = Teleprompter.shared
    @ObservedObject private var voice = Teleprompter.shared.voice
    @ObservedObject private var settings = AppSettings.shared
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
        VStack(alignment: .leading, spacing: 7) {
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
            Picker("", selection: $settings.teleprompterFollowsVoice) {
                Image(systemName: "gauge.with.dots.needle.33percent").tag(false).help(L("teleprompter.modeAuto"))
                Image(systemName: "waveform").tag(true).help(L("teleprompter.modeVoice"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 100)
            .onChange(of: settings.teleprompterFollowsVoice) { prompter.pause() }
            if settings.teleprompterFollowsVoice {
                HStack(spacing: 4) {
                    Circle().fill(voice.isListening ? Color.red : Color.gray).frame(width: 6, height: 6)
                    Text(voice.error ?? (voice.isListening ? L("voice.listening") : L("voice.idle")))
                        .lineLimit(2)
                }
                .font(.system(size: 10))
                .foregroundStyle(voice.error == nil ? .white.opacity(0.6) : .orange)
            } else {
                Stepper(value: $prompter.speed, in: 0.25...4, step: 0.25) {
                    Label(String(format: "×%.2g", prompter.speed), systemImage: "hare")
                }
            }
            Stepper(value: $prompter.fontSize, in: 14...40, step: 2) {
                Label("\(Int(prompter.fontSize)) pt", systemImage: "textformat.size")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .controlSize(.mini)
        .frame(width: 132, alignment: .leading)
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
                    PrompterText(text: prompter.text, fontSize: prompter.fontSize,
                                 readUpTo: settings.teleprompterFollowsVoice ? voice.spokenLocation : nil)
                        .frame(width: geo.size.width, height: max(prompter.textHeight, 1))
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

/// The script laid out with TextKit, so the voice follower knows where each word sits.
private struct PrompterText: NSViewRepresentable {
    let text: String
    let fontSize: Double
    /// Words before this location are dimmed (already read).
    let readUpTo: Int?

    func makeNSView(context: Context) -> PrompterTextView {
        let view = PrompterTextView()
        view.onHeight = { height in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if abs(Teleprompter.shared.textHeight - height) > 0.5 {
                        Teleprompter.shared.textHeight = height
                        Teleprompter.shared.objectWillChange.send()
                    }
                }
            }
        }
        Teleprompter.shared.yForCharacter = { [weak view] location in view?.y(forCharacter: location) ?? 0 }
        return view
    }

    func updateNSView(_ view: PrompterTextView, context: Context) {
        view.update(text: text, fontSize: fontSize, readUpTo: readUpTo)
    }
}

final class PrompterTextView: NSView {
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer()
    private var current: (String, Double, Int?)?
    var onHeight: ((CGFloat) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(text: String, fontSize: Double, readUpTo: Int?) {
        guard current.map({ $0.0 != text || $0.1 != fontSize || $0.2 != readUpTo }) ?? true else { return }
        current = (text, fontSize, readUpTo)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = fontSize * 0.25
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
        if let readUpTo, readUpTo > 0 {
            attributed.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.35),
                                    range: NSRange(location: 0, length: min(readUpTo, attributed.length)))
        }
        storage.setAttributedString(attributed)
        relayout()
    }

    override func layout() {
        super.layout()
        if container.size.width != bounds.width { relayout() }
    }

    private func relayout() {
        container.size = NSSize(width: max(bounds.width, 10), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        onHeight?(ceil(layoutManager.usedRect(for: container).height))
        needsDisplay = true
    }

    func y(forCharacter location: Int) -> CGFloat {
        guard storage.length > 0 else { return 0 }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(location, storage.length - 1))
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }

    override func draw(_ dirtyRect: NSRect) {
        layoutManager.drawGlyphs(forGlyphRange: layoutManager.glyphRange(for: container), at: .zero)
    }
}
