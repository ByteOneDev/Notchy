import AVFoundation
import SwiftUI

struct MirrorView: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)
    @ObservedObject private var calendar = CalendarService.shared

    var body: some View {
        HStack(spacing: 18) {
            Group {
                switch status {
                case .authorized:
                    CameraPreview()
                case .notDetermined:
                    placeholder(L("mirror.allow")) {
                        AVCaptureDevice.requestAccess(for: .video) { _ in
                            DispatchQueue.main.async { status = AVCaptureDevice.authorizationStatus(for: .video) }
                        }
                    }
                default:
                    placeholder(L("mirror.denied")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                }
            }
            .frame(width: 230)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.12)))
            if let event = calendar.prepEvent {
                MeetingPrepCard(event: event)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { PrivacyMonitor.shared.ignoreCamera = true }
        .onDisappear {
            // Give the camera time to turn off before announcing camera changes again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { PrivacyMonitor.shared.ignoreCamera = false }
        }
    }

    private func placeholder(_ text: String, action: @escaping () -> Void) -> some View {
        ZStack {
            Color.white.opacity(0.06)
            VStack(spacing: 8) {
                Image(systemName: "camera.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.5))
                Button(text, action: action).buttonStyle(PillButtonStyle())
            }
        }
    }
}

/// Shown next to the mirror right before a video call.
private struct MeetingPrepCard: View {
    let event: CalendarService.Event

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("prep.title"), systemImage: "video.badge.checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
            Text(event.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = event.start.timeIntervalSince(context.date)
                Text(seconds > 0 ? L("prep.startsIn", seconds.clock) : L("meeting.now"))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let url = event.meetingURL {
                    Button(L("calendar.join")) {
                        NSWorkspace.shared.open(url)
                        CalendarService.shared.endMeetingPrep()
                    }
                    .buttonStyle(PillButtonStyle(color: .green))
                }
                Button(L("prep.dismiss")) { CalendarService.shared.endMeetingPrep() }
                    .buttonStyle(PillButtonStyle(color: .white.opacity(0.15)))
            }
        }
        .frame(width: 220, alignment: .leading)
        .frame(maxHeight: .infinity)
    }
}

/// Mirrored live camera preview. The session runs only while the view is on screen.
struct CameraPreview: NSViewRepresentable {
    final class PreviewView: NSView {
        let session = AVCaptureSession()
        private let previewLayer: AVCaptureVideoPreviewLayer

        override init(frame: NSRect) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
            configure()
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }

        private func configure() {
            session.sessionPreset = .high
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let session = session
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }

        func stop() {
            let session = session
            DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
        }
    }

    func makeNSView(context: Context) -> PreviewView { PreviewView() }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) { nsView.stop() }
}
