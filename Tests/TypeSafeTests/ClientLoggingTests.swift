import Testing
@testable import TypeSafe

struct ClientLoggingTests {
    @Test func infoLogsStatusAndDebugLogsBody() async throws {
        let sink = RecordingLogger()
        let transport = MockTransport { _ in
            jsonResponse(
                status: 200,
                body: """
                {"model":"jev-latest","answers":{"n":{"type":"noul","noul":0}},"usage":{"input_tokens":0,"output_tokens":0}}
                """,
                headers: [
                    "Content-Type": "application/json",
                    "x-typesafe-request-id": "abc",
                ]
            )
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "supersecretkey", logLevel: .debug, logger: sink, transport: transport),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        _ = try await client.systemOne(state: "x", questions: Q())
        #expect(sink.lines.contains { $0.level == "info" && $0.message.contains("200") && $0.message.contains("abc") })
        #expect(sink.lines.contains { $0.level == "debug" && $0.message.contains("***") && !$0.message.contains("supersecretkey") })
    }
}
