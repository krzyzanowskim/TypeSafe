import Foundation

struct APISession: Sendable {
    let baseURL: URL
    let apiKey: String
    let defaultHeaders: [String: String]
    let timeout: Duration
    let transport: any HTTPTransport

    func request(
        method: String,
        path: String,
        body: Data?,
        options: RequestOptions
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeInterval(from: options.timeout ?? timeout)

        var sdkHeaders: [String: String?] = defaultSDKHeaders(apiKey: apiKey, retryCount: nil)
            .mapValues { Optional($0) }
        // defaultSDKHeaders omits this key when retryCount is nil; a trailing nil still strips a user value.
        sdkHeaders["X-TypeSafe-Retry-Count"] = nil
        if method == "POST", body != nil {
            sdkHeaders["Content-Type"] = "application/json"
        }

        let headers = mergeHeaders([
            defaultHeaders.mapValues { Optional($0) },
            options.headers.mapValues { Optional($0) },
            sdkHeaders,
        ])
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        return try await transport.send(request)
    }

    private func url(for path: String) -> URL {
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return URL(string: baseURL.absoluteString + suffix) ?? baseURL
    }
}

private func timeInterval(from duration: Duration) -> TimeInterval {
    let (seconds, attoseconds) = duration.components
    return TimeInterval(seconds) + TimeInterval(attoseconds) * 1e-18
}
