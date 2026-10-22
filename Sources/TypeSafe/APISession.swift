import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct APISession: Sendable {
    let baseURL: URL
    let apiKey: String
    let defaultHeaders: [String: String]
    let timeout: Duration
    let retry: RetryPolicy
    let compression: RequestCompression
    let transport: any HTTPTransport
    let logger: any TypeSafeLogger
    let random: @Sendable () -> Double
    let sleep: @Sendable (Duration) async throws -> Void
    private let requestCounter = RequestCounter()

    func request(
        method: String,
        path: String,
        body: RequestBody?,
        options: RequestOptions
    ) async throws -> (Data, HTTPURLResponse) {
        let policy = try apply(options.retry, to: retry)
        let timeout = options.timeout ?? self.timeout
        guard timeout > .zero else {
            throw TypeSafeError(message: "timeout must be a positive duration.")
        }
        let tag = "#\(requestCounter.next()) \(method) \(path)"
        let body = try body?.compressed(compression)

        var attempt = 0
        while true {
            let retriesLeft = policy.maxRetries - attempt
            let started = ContinuousClock.now
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await send(
                    method: method,
                    path: path,
                    body: body,
                    timeout: timeout,
                    options: options,
                    retryCount: attempt == 0 ? nil : attempt,
                    tag: tag
                )
            } catch is CancellationError {
                logger.info("\(tag) aborted by caller after \(formatMilliseconds(started.duration(to: .now)))")
                throw CancellationError()
            } catch let error as TimeoutError {
                logger.info("\(tag) timed out after \(formatMilliseconds(started.duration(to: .now)))")
                if retriesLeft > 0, policy.retryTimeouts {
                    try await sleepBeforeRetry(
                        attempt: attempt,
                        policy: policy,
                        tag: tag,
                        retriesLeft: retriesLeft,
                        reason: error.message
                    )
                    attempt += 1
                    continue
                }
                throw error
            } catch let error as ConnectionError {
                logger.info("\(tag) connection error after \(formatMilliseconds(started.duration(to: .now)))")
                if retriesLeft > 0, policy.retryConnectionErrors {
                    try await sleepBeforeRetry(
                        attempt: attempt,
                        policy: policy,
                        tag: tag,
                        retriesLeft: retriesLeft,
                        reason: error.message
                    )
                    attempt += 1
                    continue
                }
                throw error
            }

            let elapsed = started.duration(to: .now)
            let requestID = response.value(forHTTPHeaderField: "x-typesafe-request-id")
            var summary = "\(tag) <- \(response.statusCode) in \(formatMilliseconds(elapsed))"
            if let requestID, !requestID.isEmpty {
                summary += " (request \(requestID))"
            }
            logger.info(summary)

            if (200..<300).contains(response.statusCode) {
                logger.debug("\(tag) <- body \(describeBody(data))")
                return (data, response)
            }

            logger.debug("\(tag) <- error body \(describeBody(data))")
            let error = makeAPIError(data: data, response: response)
            if retriesLeft > 0, policy.httpStatuses.contains(response.statusCode) {
                try await sleepBeforeRetry(
                    attempt: attempt,
                    retryAfterMS: response.value(forHTTPHeaderField: "retry-after-ms"),
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                    policy: policy,
                    tag: tag,
                    retriesLeft: retriesLeft,
                    reason: "\(response.statusCode)"
                )
                attempt += 1
                continue
            }
            throw error
        }
    }

    private func send(
        method: String,
        path: String,
        body: RequestBody?,
        timeout: Duration,
        options: RequestOptions,
        retryCount: Int?,
        tag: String
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.httpBody = body?.content
        request.timeoutInterval = timeInterval(from: timeout)

        let headers = mergeHeaders([
            defaultHeaders.mapValues { Optional($0) },
            options.headers.mapValues { Optional($0) },
            ["X-TypeSafe-Retry-Count": nil],
            defaultSDKHeaders(apiKey: apiKey, retryCount: retryCount).mapValues { Optional($0) },
            ["Content-Type": body?.contentType, "Content-Encoding": body?.contentEncoding],
        ])
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        logger.debug(
            "\(tag) -> \(request.url?.absoluteString ?? "") headers=\(describeHeaders(headers)) body=\(describeBody(body?.payload))"
        )

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
        policy: RetryPolicy,
        tag: String,
        retriesLeft: Int,
        reason: String
    ) async throws {
        let delay = retryDelay(
            attempt: attempt,
            retryAfterMS: retryAfterMS,
            retryAfter: retryAfter,
            policy: policy,
            random: random
        )
        let nth = attempt + 1
        let total = attempt + retriesLeft
        logger.info("\(tag) retrying in \(formatMilliseconds(delay)) (retry \(nth)/\(total)) after \(reason)")
        do {
            try await sleep(delay)
        } catch is CancellationError {
            logger.info("\(tag) aborted by caller while waiting to retry")
            throw CancellationError()
        }
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
    if error is CancellationError || isCancelled(error) || Task.isCancelled {
        return CancellationError()
    }
    if error is TimeoutError || error is ConnectionError {
        return error
    }
    if isTimedOut(error) {
        return TimeoutError(timeout: timeout)
    }
    return ConnectionError(
        message: "Connection error: \(error.localizedDescription)",
        underlying: error
    )
}

/// Shared across session copies so `systemOne` and `models.list` keep a single sequence.
private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private func describeHeaders(_ headers: [String: String]) -> String {
    jsonObjectDescription(redactHeaders(headers))
}

private func describeBody(_ data: Data?) -> String {
    guard let data, !data.isEmpty else { return "null" }
    if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
        return jsonObjectDescription(object)
    }
    return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
}

private func jsonObjectDescription(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object) || object is String || object is NSNumber || object is NSNull,
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]),
          let string = String(data: data, encoding: .utf8)
    else {
        return String(describing: object)
    }
    return string
}

private func isTimedOut(_ error: Error) -> Bool {
    urlError(error, matches: .timedOut)
}

private func isCancelled(_ error: Error) -> Bool {
    urlError(error, matches: .cancelled)
}

private func urlError(_ error: Error, matches code: URLError.Code) -> Bool {
    if let urlError = error as? URLError, urlError.code == code {
        return true
    }
    // URLError bridges to NSError; URLSession often throws NSURLErrorDomain codes.
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == code.rawValue
}
