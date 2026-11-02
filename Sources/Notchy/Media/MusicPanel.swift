import CoreAudio
import SwiftUI

/// The dedicated music panel: big artwork, lyrics, scrubber and a full row of controls.
struct MusicPanel: View {
    @ObservedObject private var media = NowPlayingService.shared
    @ObservedObject private var lyrics = LyricsService.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if let track = media.track {
            HStack(spacing: 20) {
                ZStack(alignment: .bottomTrailing) {
                    ArtworkView(image: media.artwork, size: 116, radius: 20, isLogo: media.isLogoArtwork, tint: media.accent)
                        .shadow(color: media.accent.opacity(track.isPlaying ? 0.6 : 0.2), radius: 18)
                        .scaleEffect(track.isPlaying ? 1 : 0.93)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: track.isPlaying)
                        .onTapGesture { media.openSourceApp() }
                    SourceBadge(track: track).offset(x: 6, y: 6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(text: track.title, font: .system(size: 17, weight: .semibold))
                            Text(track.artist.isEmpty ? track.album : track.artist)
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if settings.showVisualizer {
                            AudioVisualizer(color: media.accent, playing: track.isPlaying, bars: 6)
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let position = track.position(at: context.date)
                        VStack(alignment: .leading, spacing: 5) {
                            lyricLines(at: position)
                            Spacer(minLength: 0)
                            Scrubber(position: position, duration: track.duration, color: media.accent) { media.seek(to: $0) }
                        }
                    }
                    controls(track)
                }
            }
        } else {
            MediaPlayerView()
        }
    }

    @ViewBuilder private func lyricLines(at position: TimeInterval) -> some View {
        if settings.showLyrics, let index = lyrics.lines.lastIndex(where: { $0.time <= position + 0.3 }) {
            let current = lyrics.lines[index].text
            let next = lyrics.lines.dropFirst(index + 1).first { !$0.text.isEmpty }?.text
            VStack(alignment: .leading, spacing: 1) {
                Text(current.isEmpty ? "♪" : current)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(media.accent).lineLimit(1)
                if let next {
                    Text(next).font(.system(size: 11)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                }
            }
            .id(index)
            .transition(.push(from: .bottom))
            .animation(.easeOut(duration: 0.3), value: index)
        }
    }

    private func controls(_ track: NowPlayingTrack) -> some View {
        HStack(spacing: 0) {
            OutputDeviceMenu()
            Spacer()
            HStack(spacing: 22) {
                Button { media.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 17)) }
                    .buttonStyle(HoverButtonStyle())
                Button { media.togglePlayPause() } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(HoverButtonStyle(padding: 0))
                Button { media.next() } label: { Image(systemName: "forward.fill").font(.system(size: 17)) }
                    .buttonStyle(HoverButtonStyle())
            }
            Spacer()
            Button { media.openSourceApp() } label: {
                Image(systemName: "arrow.up.forward.app").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(HoverButtonStyle())
            .help(L("music.openApp"))
        }
    }
}

/// Picks the audio output (Mac speakers, AirPods, AirPlay…).
struct OutputDeviceMenu: View {
    @State private var devices: [AudioOutputs.Device] = []

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button {
                    AudioOutputs.setDefault(device.id)
                    Haptics.tap()
                } label: {
                    if device.isDefault { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                }
            }
        } label: {
            Image(systemName: devices.first(where: \.isDefault)?.symbol ?? "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("music.output"))
        .onAppear { devices = AudioOutputs.all() }
        .onHover { if $0 { devices = AudioOutputs.all() } }
    }
}

enum AudioOutputs {
    struct Device: Identifiable {
        let id: AudioObjectID
        let name: String
        let isDefault: Bool

        var symbol: String {
            let lower = name.lowercased()
            if lower.contains("airpods max") { return "airpodsmax" }
            if lower.contains("airpods pro") { return "airpodspro" }
            if lower.contains("airpods") { return "airpods" }
            if lower.contains("macbook") || lower.contains("haut-parleurs") || lower.contains("speakers") { return "laptopcomputer" }
            if lower.contains("display") || lower.contains("écran") || lower.contains("hdmi") { return "tv" }
            return "hifispeaker.fill"
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func all() -> [Device] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        let current = defaultOutput()
        return ids.compactMap { id in
            // Output devices only: they have output streams.
            var streams = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var nameAddr = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name) == noErr,
                  let value = name?.takeRetainedValue() as String? else { return nil }
            return Device(id: id, name: value, isDefault: id == current)
        }
    }

    static func defaultOutput() -> AudioObjectID {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func setDefault(_ id: AudioObjectID) {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
    }
}
