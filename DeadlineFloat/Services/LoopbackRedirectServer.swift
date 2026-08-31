import Darwin
import Foundation

/// A single-shot HTTP listener on `127.0.0.1` that catches Google's OAuth
/// redirect.
///
/// This is the loopback flow Google documents for **Desktop app** clients: the
/// system browser performs the sign-in (so the app never sees the password) and
/// redirects back to an ephemeral port bound to the loopback interface only —
/// nothing outside this Mac can reach it. The listener closes as soon as it has
/// the authorization code.
final class LoopbackRedirectServer: @unchecked Sendable {
    struct Callback: Sendable, Equatable {
        var parameters: [String: String]
        var code: String? { parameters["code"] }
        var state: String? { parameters["state"] }
        var error: String? { parameters["error"] }
    }

    enum ServerError: LocalizedError, Equatable {
        case socketFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .socketFailed(let detail): return "Could not open the local sign-in listener (\(detail))."
            case .timedOut: return "Timed out waiting for Google to redirect back to DeadlineFloat."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.niravsurabhi.DeadlineFloat.loopback")
    private let lock = NSLock()

    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var continuation: CheckedContinuation<Callback, Error>?
    private var isFinished = false

    private(set) var port: UInt16 = 0

    var redirectURI: String { "http://127.0.0.1:\(port)" }

    deinit { closeSocket() }

    // MARK: - Lifecycle

    /// Binds an ephemeral loopback port and begins listening. Returns the port.
    @discardableResult
    func start() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed("socket: \(errnoDescription())") }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0                                   // kernel picks the port
        address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian    // 127.0.0.1 only

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            throw ServerError.socketFailed("bind: \(errnoDescription())")
        }
        guard listen(fd, 4) == 0 else {
            close(fd)
            throw ServerError.socketFailed("listen: \(errnoDescription())")
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }

        listenFD = fd
        port = UInt16(bigEndian: boundAddress.sin_port)

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in self?.acceptConnection() }
        readSource.setCancelHandler { [weak self] in self?.closeSocket() }
        source = readSource
        readSource.resume()

        Log.auth.info("Loopback redirect listener ready on port \(self.port, privacy: .public)")
        return port
    }

    /// Waits for a redirect carrying `code` or `error`. Other requests (the
    /// browser's `favicon.ico`, for instance) are answered and ignored.
    func waitForCallback(timeout: TimeInterval = 300) async throws -> Callback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Callback, Error>) in
                lock.lock()
                if isFinished {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                lock.unlock()

                queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(with: .failure(ServerError.timedOut))
                }
            }
        } onCancel: {
            finish(with: .failure(CancellationError()))
        }
    }

    func stop() {
        finish(with: .failure(CancellationError()))
    }

    // MARK: - Connection handling

    private func acceptConnection() {
        var clientAddress = sockaddr()
        var length = socklen_t(MemoryLayout<sockaddr>.size)
        let client = accept(listenFD, &clientAddress, &length)
        guard client >= 0 else { return }
        defer { close(client) }

        var buffer = [UInt8](repeating: 0, count: 16_384)
        let bytesRead = read(client, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let request = String(decoding: buffer[0..<bytesRead], as: UTF8.self)
        let parameters = Self.queryParameters(fromRequest: request)
        let isFinal = parameters["code"] != nil || parameters["error"] != nil

        let body = Self.responseHTML(success: parameters["code"] != nil, error: parameters["error"])
        let bodyData = Data(body.utf8)
        let head = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var response = Data(head.utf8)
        response.append(bodyData)
        response.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(client, base.advanced(by: offset), raw.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }

        if isFinal {
            finish(with: .success(Callback(parameters: parameters)))
        }
    }

    private func finish(with result: Result<Callback, Error>) {
        lock.lock()
        guard !isFinished else { lock.unlock(); return }
        isFinished = true
        let pending = continuation
        continuation = nil
        lock.unlock()

        source?.cancel()
        source = nil
        pending?.resume(with: result)
    }

    private func closeSocket() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
    }

    private func errnoDescription() -> String { String(cString: strerror(errno)) }

    // MARK: - Parsing

    /// Pulls the query parameters out of an HTTP request's start line.
    static func queryParameters(fromRequest request: String) -> [String: String] {
        guard let line = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first
                ?? request.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        else { return [:] }

        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return [:] }
        let target = String(parts[1])

        guard let components = URLComponents(string: "http://127.0.0.1" + target),
              let items = components.queryItems
        else { return [:] }

        var parameters: [String: String] = [:]
        for item in items where item.value != nil {
            parameters[item.name] = item.value
        }
        return parameters
    }

    /// The page the browser shows once the redirect lands.
    static func responseHTML(success: Bool, error: String?) -> String {
        let title = success ? "DeadlineFloat is connected" : "Sign-in was not completed"
        var reason = ""
        if let error, !error.isEmpty { reason = " (" + error + ")" }
        let detail = success
            ? "You can close this tab and return to DeadlineFloat."
            : "DeadlineFloat did not receive permission" + reason + ". You can close this tab and try again."
        let accent = success ? "#34c759" : "#ff9f0a"

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
          :root { color-scheme: light dark; }
          body { margin: 0; min-height: 100vh; display: grid; place-items: center;
                 font: 400 16px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
                 background: #f2f2f7; color: #1c1c1e; }
          @media (prefers-color-scheme: dark) { body { background: #1c1c1e; color: #f2f2f7; } .card { background: #2c2c2ecc !important; } }
          .card { background: #ffffffcc; backdrop-filter: blur(24px); border-radius: 20px; padding: 40px 44px;
                  box-shadow: 0 20px 60px rgba(0,0,0,.18); text-align: center; max-width: 26rem; }
          .dot { width: 12px; height: 12px; border-radius: 50%; background: \(accent); display: inline-block; margin-right: 8px; }
          h1 { font-size: 1.25rem; margin: 0 0 .5rem; letter-spacing: -.01em; }
          p { margin: 0; opacity: .7; font-size: .95rem; }
        </style>
        </head>
        <body><div class="card"><h1><span class="dot"></span>\(title)</h1><p>\(detail)</p></div></body>
        </html>
        """
    }
}
