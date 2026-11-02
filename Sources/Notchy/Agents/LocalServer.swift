import Foundation
import Network

/// Minimal HTTP/1.1 server on 127.0.0.1, used by Claude Code hooks, its status line and Codex.
/// Only reachable from this Mac.
final class LocalServer: @unchecked Sendable {
    static let port: UInt16 = 47812

    struct Request {
        let method: String
        let path: String
        let body: Data
    }

    struct Response {
        var status = 200
        var contentType = "application/json"
        var body = Data("{}".utf8)

        static func json(_ object: Any) -> Response {
            Response(body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
        }

        static func text(_ text: String) -> Response {
            Response(contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
        }
    }

    /// Called on the main queue; call `respond` once, possibly later (permission prompts wait for the user).
    var handler: (@MainActor (Request, @escaping @MainActor (Response) -> Void) -> Void)?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "notchy.localserver")

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else {
            NSLog("Notchy: local server could not start")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state { NSLog("Notchy: local server failed: \(error)") }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.dispatch(request, on: connection)
            } else if isComplete || error != nil || buffer.count > 8 << 20 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    /// Returns the request once headers and the full body have arrived.
    private static func parse(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }
        return Request(method: String(requestLine[0]), path: String(requestLine[1]),
                       body: data.subdata(in: bodyStart..<(bodyStart + length)))
    }

    private func dispatch(_ request: Request, on connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let handler = self?.handler else { return Self.send(Response(status: 503), on: connection) }
                var answered = false
                handler(request) { response in
                    guard !answered else { return }
                    answered = true
                    Self.send(response, on: connection)
                }
            }
        }
    }

    private static func send(_ response: Response, on connection: NWConnection) {
        let reason = response.status == 200 ? "OK" : "Error"
        var data = Data("HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n".utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}
