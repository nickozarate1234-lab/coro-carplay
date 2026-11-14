import Foundation
import Network

/// OAuth callback bound exclusively to this iPhone's loopback interface.
/// The Safari sheet remains in the foreground while authorizing.
@MainActor
final class LoopbackCallback {
    static let redirect = "http://127.0.0.1:43821/callback"
    private var listener: NWListener?
    private var callback: ((URL) -> Void)?
    private var connections: [NWConnection] = []

    func start(callback: @escaping (URL) -> Void) async throws {
        stop()
        self.callback = callback
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 43821)
        let server = try NWListener(using: parameters)
        listener = server
        server.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.listener != nil else { connection.cancel(); return }
                guard self.connections.count < 8 else { connection.cancel(); return }
                self.connections.append(connection)
                connection.start(queue: .main)
                self.receive(connection, buffer: Data())
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    self?.close(connection)
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var completed = false
            server.stateUpdateHandler = { state in
                guard !completed else { return }
                switch state {
                case .ready:
                    completed = true
                    continuation.resume()
                case .failed(let error):
                    completed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    completed = true
                    continuation.resume(throwing: CancellationError())
                default: break
                }
            }
            server.start(queue: .main)
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var collected = buffer
                if let data { collected.append(data) }
                guard error == nil, collected.count < 8192 else { self.close(connection); return }
                guard let request = String(data: collected, encoding: .utf8), request.contains("\r\n\r\n") else {
                    if complete { self.close(connection) } else { self.receive(connection, buffer: collected) }
                    return
                }
                let parts = request.components(separatedBy: "\r\n").first?.components(separatedBy: " ") ?? []
                guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/callback?"),
                      let url = URL(string: "http://127.0.0.1:43821" + parts[1]), url.path == "/callback" else {
                    self.reply(connection, status: "404 Not Found", message: "No disponible.")
                    return
                }
                self.reply(connection, status: "200 OK", message: "Puedes volver a Coro. Esta ventana se cerrara al terminar la conexion.") { [weak self] in
                    self?.callback?(url)
                }
            }
        }
    }

    private func reply(_ connection: NWConnection, status: String, message: String, completion: (() -> Void)? = nil) {
        let body = Data(message.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nPragma: no-cache\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in
                self?.close(connection)
                completion?()
            }
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        callback = nil
    }
}
