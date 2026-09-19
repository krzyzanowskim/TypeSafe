import Foundation
import Testing
@testable import TypeSafe

struct SystemOneTests {
    @Test func postsTypedQuestionsAndDecodesAnswers() async throws {
        let transport = MockTransport { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
            #expect(body?["model"] as? String == "jev-latest")
            #expect(body?["state"] as? String == "charged twice")
            let questions = try #require(body?["questions"] as? [String: Any])
            #expect((questions["isBilling"] as? [String: Any])?["type"] as? String == "noul")
            return jsonResponse(
                status: 200,
                body: """
                {
                  "model": "jev-latest",
                  "answers": { "isBilling": { "type": "noul", "noul": 0.88 } },
                  "usage": { "input_tokens": 3, "output_tokens": 1 }
                }
                """
            )
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "test-key", transport: transport),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var isBilling = Noul("Is this about billing?")
            struct Answers: Decodable, Sendable {
                var isBilling: Noul.Answer
            }
        }
        let result = try await client.systemOne(state: "charged twice", questions: Q())
        #expect(result.answers.isBilling.noul == 0.88)
        #expect(result.usage.inputTokens == 3)
    }

    @Test func emptyQuestionsThrowBeforeNetwork() async throws {
        let transport = MockTransport { _ in
            Issue.record("network should not be called")
            return jsonResponse(status: 200, body: "{}")
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", transport: transport),
            environment: [:]
        )
        struct Empty: SystemOneQuestions {
            struct Answers: Decodable, Sendable {}
        }
        let error = try await #require(throws: TypeSafeError.self) {
            try await client.systemOne(state: "x", questions: Empty())
        }
        #expect(error == .emptyQuestions)
    }

    @Test func modelOverrideSent() async throws {
        let saw = Box<String?>(nil)
        let transport = MockTransport { request in
            let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
            saw.value = body?["model"] as? String
            return jsonResponse(
                status: 200,
                body: """
                {"model":"jev-1","answers":{"n":{"type":"noul","noul":0.1}},"usage":{"input_tokens":1,"output_tokens":1}}
                """
            )
        }
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", transport: transport),
            environment: [:]
        )
        struct Q: SystemOneQuestions {
            var n = Noul("n?")
            struct Answers: Decodable, Sendable { var n: Noul.Answer }
        }
        _ = try await client.systemOne(state: "x", questions: Q(), model: "jev-1")
        #expect(saw.value == "jev-1")
    }
}
