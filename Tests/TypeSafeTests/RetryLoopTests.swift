import Foundation
import Testing
@testable import TypeSafe

struct RetryLoopTests {
    @Test func retries429ThenSucceeds() async throws {
        let counts = Box<[String?]>([])
        let transport = MockTransport.sequence([
            { request in
                counts.value.append(request.value(forHTTPHeaderField: "X-TypeSafe-Retry-Count"))
                return jsonResponse(status: 429, body: "{\"error\":\"slow down\"}", headers: [
                    "Content-Type": "application/json",
                    "retry-after-ms": "0",
                ])
            },
            { request in
                counts.value.append(request.value(forHTTPHeaderField: "X-TypeSafe-Retry-Count"))
                return jsonResponse(
                    status: 200,
                    body: """
                    {"model":"jev-latest","answers":{"n":{"type":"noul","noul":1}},"usage":{"input_tokens":1,"output_tokens":1}}
                    """
                )
            },
        ])
        let client = try TypeSafeClient(
            Configuration(
                apiKey: "k",
                retry: RetryOverride(backoffInitial: .zero, backoffJitter: 0),
                transport: transport
            ),
            environment: [:],
            sleep: { _ in }
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        let result = try await client.systemOne(state: "x", questions: Q())
        #expect(result.answers.n.noul == 1)
        #expect(counts.value == [nil, "1"])
    }

    @Test func doesNotRetry400() async throws {
        let calls = Box(0)
        let transport = MockTransport { _ in
            calls.value += 1
            return jsonResponse(status: 400, body: "{\"error\":\"nope\"}")
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", transport: transport),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        let error = try await #require(throws: APIError.self) {
            try await client.systemOne(state: "x", questions: Q())
        }
        #expect(error.status == 400)
        #expect(error.message == "400 nope")
        #expect(calls.value == 1)
    }

    @Test func exhaustsRetries() async throws {
        let calls = Box(0)
        let transport = MockTransport { _ in
            calls.value += 1
            return jsonResponse(
                status: 500,
                body: "oops",
                headers: ["x-typesafe-request-id": "req-1", "Content-Type": "text/plain"]
            )
        }
        let client = try TypeSafeClient(
            Configuration(
                apiKey: "k",
                retry: RetryOverride(maxRetries: 2, backoffInitial: .zero, backoffJitter: 0),
                transport: transport
            ),
            environment: [:],
            sleep: { _ in }
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        let error = try await #require(throws: APIError.self) {
            try await client.systemOne(state: "x", questions: Q())
        }
        #expect(error.status == 500)
        #expect(error.requestID == "req-1")
        #expect(calls.value == 3)
    }

    @Test func cancelWhileWaitingToRetryLogsOnce() async throws {
        let sink = RecordingLogger()
        let transport = MockTransport { _ in
            jsonResponse(status: 503, body: "{\"error\":\"busy\"}")
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", logLevel: .info, logger: sink, transport: transport),
            environment: [:],
            sleep: { _ in throw CancellationError() }
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        try await #require(throws: CancellationError.self) {
            try await client.systemOne(state: "x", questions: Q())
        }
        let aborted = sink.lines.filter { $0.message.contains("aborted") }.map(\.message)
        #expect(aborted.count == 1)
        #expect(aborted.first?.hasSuffix("aborted by caller while waiting to retry") == true)
    }

    @Test func userRetryCountHeaderIsDropped() async throws {
        let count = Box<String?>("unset")
        let transport = MockTransport { request in
            count.value = request.value(forHTTPHeaderField: "X-TypeSafe-Retry-Count")
            return jsonResponse(
                status: 200,
                body: """
                {"model":"jev-latest","answers":{"n":{"type":"noul","noul":0}},"usage":{"input_tokens":0,"output_tokens":0}}
                """
            )
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", defaultHeaders: ["x-typesafe-retry-count": "7"], transport: transport),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        _ = try await client.systemOne(state: "x", questions: Q())
        #expect(count.value == nil)
    }

    @Test func userCannotOverrideAuthorization() async throws {
        let auth = Box<String?>(nil)
        let transport = MockTransport { request in
            auth.value = request.value(forHTTPHeaderField: "Authorization")
            return jsonResponse(
                status: 200,
                body: """
                {"model":"jev-latest","answers":{"n":{"type":"noul","noul":0}},"usage":{"input_tokens":0,"output_tokens":0}}
                """
            )
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "real", defaultHeaders: ["Authorization": "Bearer leaked"], transport: transport),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        _ = try await client.systemOne(
            state: "x",
            questions: Q(),
            options: RequestOptions(headers: ["Authorization": "Bearer also-leaked"])
        )
        #expect(auth.value == "Bearer real")
    }
}
