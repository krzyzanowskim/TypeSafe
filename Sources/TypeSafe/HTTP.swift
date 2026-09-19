import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Last source wins by lowercase name so callers cannot keep a stale casing; `nil` drops a key.
func mergeHeaders(_ sources: [[String: String?]]) -> [String: String] {
    var entries: [String: (name: String, value: String)] = [:]
    for source in sources {
        for (name, value) in source {
            let key = name.lowercased()
            if let value {
                entries[key] = (name, value)
            } else {
                entries.removeValue(forKey: key)
            }
        }
    }
    var merged: [String: String] = [:]
    merged.reserveCapacity(entries.count)
    for entry in entries.values {
        merged[entry.name] = entry.value
    }
    return merged
}

func defaultSDKHeaders(apiKey: String, retryCount: Int?) -> [String: String] {
    let identity = "typesafe-sdk-swift/\(version)"
    var headers: [String: String] = [
        "Authorization": "Bearer \(apiKey)",
        "Accept": "application/json",
        "User-Agent": identity,
        "X-TypeSafe-SDK": identity,
        "X-TypeSafe-Runtime": "swift/\(swiftVersion) (\(osName))",
    ]
    if let retryCount {
        headers["X-TypeSafe-Retry-Count"] = String(retryCount)
    }
    return headers
}

private let swiftVersion = "6.0"
private let osName = ProcessInfo.processInfo.operatingSystemVersionString

struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError()
        }
        return (data, httpResponse)
    }
}
