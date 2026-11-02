import AppKit
import CoreWLAN
import SwiftUI

/// Network interfaces of the Mac, read with getifaddrs.
enum Interfaces {
    struct Address {
        let name: String
        let ip: String
    }

    static func ipv4() -> [Address] {
        var result: [Address] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            result.append(Address(name: String(cString: entry.ifa_name), ip: String(cString: host)))
        }
        return result
    }

    /// The Mac's address on the local network (Wi-Fi or Ethernet).
    static var localIP: String? { ipv4().first { $0.name.hasPrefix("en") }?.ip }

    /// A VPN shows up as a tunnel interface with an IPv4 address.
    static var vpnActive: Bool {
        ipv4().contains { address in ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains { address.name.hasPrefix($0) } }
    }

    /// Name of the Wi-Fi network; macOS only gives it to apps allowed to use the location.
    static var wifiName: String? { CWWiFiClient.shared().interface()?.ssid() }
}

@MainActor
final class NetworkInfo: ObservableObject {
    static let shared = NetworkInfo()

    struct ListeningPort: Identifiable, Equatable {
        let pid: Int32
        let process: String
        let port: Int
        var id: String { "\(pid):\(port)" }
    }

    enum SpeedTest: Equatable {
        case idle, running, failed
        case result(down: Double, up: Double)
    }

    @Published private(set) var localIP: String?
    @Published private(set) var publicIP: String?
    @Published private(set) var wifiName: String?
    @Published private(set) var vpnActive = false
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var speed: SpeedTest = .idle
    @Published private(set) var copied: String?
    private var publicIPDate = Date.distantPast

    func refresh() {
        localIP = Interfaces.localIP
        wifiName = Interfaces.wifiName
        vpnActive = Interfaces.vpnActive
        Task { ports = await Self.listeningPorts() }
        // The public address barely changes: ask for it at most every five minutes.
        guard Date.now.timeIntervalSince(publicIPDate) > 300 else { return }
        publicIPDate = .now
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://api.ipify.org")!) else {
                publicIPDate = .distantPast
                return
            }
            publicIP = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Haptics.tap()
        withAnimation(.snappy) { copied = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.copied == text { withAnimation(.snappy) { self.copied = nil } }
        }
    }

    func stop(_ port: ListeningPort) {
        kill(port.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }
    }

    /// Apple's own test (the same as `networkQuality` in the Terminal), about fifteen seconds.
    func runSpeedTest() {
        guard speed != .running else { return }
        speed = .running
        Task {
            speed = await Task.detached { () -> SpeedTest in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
                process.arguments = ["-c"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return .failed }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let down = json["dl_throughput"] as? Double, let up = json["ul_throughput"] as? Double else { return .failed }
                return .result(down: down / 1_000_000, up: up / 1_000_000)
            }.value
        }
    }

    /// TCP ports the user's processes listen on.
    nonisolated private static func listeningPorts() async -> [ListeningPort] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            var result: [ListeningPort] = []
            var pid: Int32 = 0
            var command = ""
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let value = String(line.dropFirst())
                switch line.first {
                case "p": pid = Int32(value) ?? 0
                case "c": command = value
                case "n":
                    if let port = value.split(separator: ":").last.flatMap({ Int($0) }),
                       !result.contains(where: { $0.pid == pid && $0.port == port }) {
                        result.append(ListeningPort(pid: pid, process: command, port: port))
                    }
                default: break
                }
            }
            return result.sorted { $0.port < $1.port }
        }.value
    }
}

struct NetworkWidget: View {
    @ObservedObject private var network = NetworkInfo.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .network) {
                if let wifi = network.wifiName {
                    Text(wifi).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
            }
            addressRow(L("network.local"), network.localIP)
            addressRow(L("network.public"), network.publicIP)
            HStack(spacing: 6) {
                Text("VPN").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 4)
                Circle().fill(network.vpnActive ? Color.green : Color.white.opacity(0.25)).frame(width: 6, height: 6)
                Text(network.vpnActive ? L("focus.on") : L("focus.off")).font(.system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                speedButton
                portsMenu
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { network.refresh() }
    }

    private func addressRow(_ label: String, _ ip: String?) -> some View {
        Button {
            if let ip { network.copy(ip) }
        } label: {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 4)
                if let ip, network.copied == ip {
                    Label(L("network.copied"), systemImage: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                } else {
                    Text(ip ?? "—").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Image(systemName: "doc.on.doc").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(ip == nil)
        .help(L("network.copy"))
    }

    private var speedButton: some View {
        Button { network.runSpeedTest() } label: {
            HStack(spacing: 5) {
                switch network.speed {
                case .idle:
                    Image(systemName: "speedometer")
                    Text(L("network.speed"))
                case .running:
                    ProgressView().controlSize(.mini).tint(.white)
                    Text(L("network.testing"))
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(L("network.speed"))
                case let .result(down, up):
                    Text("↓ \(Int(down.rounded()))  ↑ \(Int(up.rounded())) Mb/s").monospacedDigit()
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(network.speed == .running)
    }

    private var portsMenu: some View {
        Menu {
            if network.ports.isEmpty { Text(L("network.noPorts")) }
            ForEach(network.ports) { port in
                Menu("\(port.port) · \(port.process)") {
                    Button(L("network.openBrowser")) {
                        if let url = URL(string: "http://localhost:\(port.port)") { NSWorkspace.shared.open(url) }
                    }
                    Button(L("network.copyAddress")) { network.copy("localhost:\(port.port)") }
                    Divider()
                    Button(L("network.stopProcess"), role: .destructive) { network.stop(port) }
                }
            }
        } label: {
            Text(L("network.ports", network.ports.count)).font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}
