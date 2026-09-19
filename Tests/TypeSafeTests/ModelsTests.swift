import Testing
@testable import TypeSafe

struct ModelsTests {
    @Test func listsModels() async throws {
        let transport = MockTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/models")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
            return jsonResponse(
                status: 200,
                body: """
                {"models":[{"name":"jev-latest","description":"flagship","release_date":"2026-01-01"}]}
                """
            )
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", transport: transport),
            environment: [:]
        )
        let models = try await client.models.list()
        #expect(models == [
            ModelCard(name: "jev-latest", description: "flagship", releaseDate: "2026-01-01")
        ])
    }

    @Test func unexpectedShapeThrows() async throws {
        let transport = MockTransport { _ in
            jsonResponse(status: 200, body: "{\"data\":[]}")
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", transport: transport),
            environment: [:]
        )
        let error = try await #require(throws: TypeSafeError.self) {
            try await client.models.list()
        }
        #expect(error == .unexpectedModelsPayload)
    }
}
