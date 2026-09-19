import Foundation
import Testing
import TypeSafe

private let hasAPIKey: Bool = {
    guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    else { return false }
    return !key.isEmpty
}()

struct IntegrationTests {
    @Test(.enabled(if: hasAPIKey))
    func listsModels() async throws {
        let client = try TypeSafeClient()
        let models = try await client.models.list()
        #expect(!models.isEmpty)
        #expect(models.contains { $0.name.contains("jev") })
    }

    @Test(.enabled(if: hasAPIKey))
    func systemOneNoul() async throws {
        let client = try TypeSafeClient()
        struct Q: SystemOneQuestions {
            var billing = Noul("Is this about billing?")
            struct Answers: Decodable, Sendable {
                var billing: Noul.Answer
            }
        }
        let result = try await client.systemOne(
            state: "I was charged twice. Please refund.",
            questions: Q()
        )
        #expect(result.answers.billing.noul > 0.5)
        #expect(result.usage.inputTokens > 0)
    }
}
