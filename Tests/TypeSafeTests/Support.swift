import Foundation
@testable import TypeSafe

func encodeJSON<T: Encodable>(_ value: T) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

func decodeJSON<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

func jsonResponse(
    status: Int,
    body: String,
    headers: [String: String] = ["Content-Type": "application/json"],
    url: URL = URL(string: "https://api.typesafe.ai/")!
) -> (Data, HTTPURLResponse) {
    let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
    return (Data(body.utf8), response)
}

struct MockTransport: HTTPTransport {
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    static func sequence(
        _ handlers: [@Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)]
    ) -> MockTransport {
        let index = Box(0)
        return MockTransport { request in
            let i = index.value
            index.value += 1
            return try await handlers[i](request)
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}
