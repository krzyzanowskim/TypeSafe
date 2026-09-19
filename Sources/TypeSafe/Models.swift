import Foundation

public struct Models: Sendable {
    let session: APISession

    init(session: APISession) {
        self.session = session
    }

    public func list(options: RequestOptions = RequestOptions()) async throws -> [ModelCard] {
        let (data, _) = try await session.request(
            method: "GET",
            path: "/v1/models",
            body: nil,
            options: options
        )
        do {
            return try JSONDecoder().decode(ModelsWire.self, from: data).models
        } catch {
            throw TypeSafeError.unexpectedModelsPayload
        }
    }
}

private struct ModelsWire: Decodable {
    var models: [ModelCard]
}
