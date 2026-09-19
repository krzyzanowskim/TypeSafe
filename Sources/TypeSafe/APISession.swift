import Foundation

struct APISession: Sendable {
    let baseURL: URL
    let apiKey: String
    let defaultHeaders: [String: String]
    let timeout: Duration
    let retry: RetryPolicy
    let transport: any HTTPTransport
    let random: @Sendable () -> Double
    let sleep: @Sendable (Duration) async throws -> Void

    func request(
        method: String,
        path: String,
        body: Data?,
        options: RequestOptions
    ) async throws -> (Data, HTTPURLResponse) {
        let policy = try apply(options.retry, to: retry)
        let timeout = options.timeout ?? self.timeout

        var attempt = 0
        while true {
            let retriesLeft = policy.maxRetries - attempt
            do {
                let (data, response) = try await send(
                    method: method,
                    path: path,
                    body: body,
                    timeout: timeout,
                    options: options,
                    retryCount: attempt == 0 ? nil : attempt
                )

                if (200..<300).contains(response.statusCode) {
                    return (data, response)
                }

                let error = makeAPIError(data: data, response: response)
                if retriesLeft > 0, policy.httpStatuses.contains(response.statusCode) {
                    try await sleepBeforeRetry(
                        attempt: attempt,
                        retryAfterMS: response.value(forHTTPHeaderField: "retry-after-ms"),
                        retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                        policy: policy
                    )
                    attempt += 1
                    continue
                }
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch is TimeoutError where retriesLeft > 0 && policy.retryTimeouts {
                try await sleepBeforeRetry(attempt: attempt, policy: policy)
                attempt += 1
            } catch is ConnectionError where retriesLeft > 0 && policy.retryConnectionErrors {
                try await sleepBeforeRetry(attempt: attempt, policy: policy)
                attempt += 1
            }
        }
    }

    private func send(
        method: String,
        path: String,
        body: Data?,
        timeout: Duration,
        options: RequestOptions,
        retryCount: Int?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeInterval(from: timeout)

        var sdkHeaders: [String: String?] = defaultSDKHeaders(apiKey: apiKey, retryCount: retryCount)
            .mapValues { Optional($0) }
        // defaultSDKHeaders omits this key when retryCount is nil; a trailing nil still strips a user value.
        if retryCount == nil {
            sdkHeaders["X-TypeSafe-Retry-Count"] = nil
        }
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

        do {
            return try await transport.send(request)
        } catch {
            throw mapTransportError(error, timeout: timeout)
        }
    }

    private func sleepBeforeRetry(
        attempt: Int,
        retryAfterMS: String? = nil,
        retryAfter: String? = nil,
        policy: RetryPolicy
    ) async throws {
        let delay = retryDelay(
            attempt: attempt,
            retryAfterMS: retryAfterMS,
            retryAfter: retryAfter,
            policy: policy,
            random: random
        )
        try await sleep(delay)
    }

    private func url(for path: String) -> URL {
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return URL(string: baseURL.absoluteString + suffix) ?? baseURL
    }
}

private func makeAPIError(data: Data, response: HTTPURLResponse) -> APIError {
    APIError(
        status: response.statusCode,
        body: parseErrorBody(data),
        headers: httpHeaders(from: response),
        requestID: response.value(forHTTPHeaderField: "x-typesafe-request-id"),
        retryAfter: parseRetryAfter(
            retryAfterMS: response.value(forHTTPHeaderField: "retry-after-ms"),
            retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
            now: Date()
        )
    )
}

private func parseErrorBody(_ data: Data) -> JSONValue? {
    guard !data.isEmpty else { return nil }
    if let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
        return value
    }
    return String(data: data, encoding: .utf8).map(JSONValue.string)
}

private func httpHeaders(from response: HTTPURLResponse) -> [String: String] {
    var headers: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
        let name = key as? String ?? String(describing: key)
        headers[name] = value as? String ?? String(describing: value)
    }
    return headers
}

private func timeInterval(from duration: Duration) -> TimeInterval {
    let (seconds, attoseconds) = duration.components
    return TimeInterval(seconds) + TimeInterval(attoseconds) * 1e-18
}

private func mapTransportError(_ error: Error, timeout: Duration) -> Error {
    if error is CancellationError || Task.isCancelled {
        return CancellationError()
    }
    if isTimedOut(error) {
        return TimeoutError(timeout: timeout)
    }
    return ConnectionError(
        message: "Connection error: \(error.localizedDescription)",
        underlying: error
    )
}

private func isTimedOut(_ error: Error) -> Bool {
    if let urlError = error as? URLError, urlError.code == .timedOut {
        return true
    }
    // URLError bridges to NSError; thrown timeouts often arrive as NSURLErrorDomain/-1001.
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue
}
