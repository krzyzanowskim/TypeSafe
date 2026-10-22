import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TypeSafe

struct ReliabilityTests {
    @Test func mapsTimedOutToTimeoutError() async throws {
        let transport = MockTransport { _ in throw URLError(.timedOut) }
        let client = try TypeSafeClient(
            Configuration(
                apiKey: "k",
                retry: RetryOverride(retryTimeouts: false),
                timeout: .milliseconds(50),
                transport: transport
            ),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        let error = try await #require(throws: TimeoutError.self) {
            try await client.systemOne(state: "x", questions: Q())
        }
        #expect(error.timeout == .milliseconds(50))
    }

    @Test func retriesConnectionErrorWhenEnabled() async throws {
        let calls = Box(0)
        let transport = MockTransport { _ in
            calls.value += 1
            if calls.value == 1 {
                throw URLError(.cannotConnectToHost)
            }
            return jsonResponse(
                status: 200,
                body: """
                {"model":"jev-latest","answers":{"n":{"type":"noul","noul":0.2}},"usage":{"input_tokens":1,"output_tokens":1}}
                """
            )
        }
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
        #expect(result.answers.n.noul == 0.2)
        #expect(calls.value == 2)
    }

    @Test func cancellationIsNotRetried() async throws {
        let calls = Box(0)
        let transport = MockTransport { _ in
            calls.value += 1
            throw CancellationError()
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", transport: transport),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        try await #require(throws: CancellationError.self) {
            try await client.systemOne(state: "x", questions: Q())
        }
        #expect(calls.value == 1)
    }

    @Test func urlErrorCancelledIsNotRetried() async throws {
        let calls = Box(0)
        let transport = MockTransport { _ in
            calls.value += 1
            throw URLError(.cancelled)
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", transport: transport),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        try await #require(throws: CancellationError.self) {
            try await client.systemOne(state: "x", questions: Q())
        }
        #expect(calls.value == 1)
    }

    @Test func doesNotWrapExistingConnectionError() async throws {
        let transport = MockTransport { _ in
            throw ConnectionError(message: "upstream down")
        }
        let client = try TypeSafeClient(
            Configuration(
                apiKey: "k",
                retry: RetryOverride(retryConnectionErrors: false),
                transport: transport
            ),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        let error = try await #require(throws: ConnectionError.self) {
            try await client.systemOne(state: "x", questions: Q())
        }
        #expect(error.message == "upstream down")
    }

    @Test func rejectsNonPositivePerCallTimeout() async throws {
        let transport = MockTransport { _ in
            Issue.record("network should not be called")
            return jsonResponse(status: 200, body: "{}")
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", transport: transport),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        let error = try await #require(throws: TypeSafeError.self) {
            try await client.systemOne(
                state: "x",
                questions: Q(),
                options: RequestOptions(timeout: .zero)
            )
        }
        #expect(error.message == "timeout must be a positive duration.")
    }
}
