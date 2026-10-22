import Testing
@testable import TypeSafe

struct TicketQuestions: SystemOneQuestions {
    var category = Choice<Category>("What is this ticket about?")
    var isBilling = Noul("Is this ticket about billing?")
    var urgency = try! Score("How urgent is this ticket?", levels: ["can wait", "this week", "today"])

    struct Answers: Decodable, Sendable {
        var category: Choice<Category>.Answer
        var isBilling: Noul.Answer
        var urgency: Score.Answer
    }
}

struct ResultTests {
    @Test func decodesTypedAnswers() throws {
        let json = """
        {
          "model": "jev-latest",
          "answers": {
            "category": {
              "type": "choice",
              "choice": "billing",
              "confidence": 0.82,
              "probabilities": {"billing": 0.8, "technical": 0.15, "other": 0.05}
            },
            "isBilling": { "type": "noul", "noul": 0.91 },
            "urgency": {
              "type": "score",
              "score": 1.6,
              "confidence": 0.7,
              "legend": {"0": "can wait", "1": "this week", "2": "today"},
              "probabilities": {"0": 0.1, "1": 0.2, "2": 0.7}
            }
          },
          "usage": { "input_tokens": 12, "output_tokens": 4 }
        }
        """
        let result = try decodeJSON(json, as: SystemOneResult<TicketQuestions.Answers>.self)
        #expect(result.model == "jev-latest")
        #expect(result.answers.category.choice == .billing)
        #expect(result.answers.category.probabilities[.technical] == 0.15)
        #expect(result.answers.isBilling.noul == 0.91)
        #expect(result.answers.urgency.score == 1.6)
        #expect(result.usage.inputTokens == 12)
        #expect(result.usage.outputTokens == 4)
    }

    @Test func nullTokenCountsDecode() throws {
        let usage = try decodeJSON(#"{"input_tokens": null, "output_tokens": 4}"#, as: Usage.self)
        #expect(usage.inputTokens == nil)
        #expect(usage.outputTokens == 4)
    }

    @Test func unknownChoiceLabelFails() {
        let json = """
        {
          "type": "choice",
          "choice": "not-a-label",
          "confidence": 1,
          "probabilities": {"not-a-label": 1}
        }
        """
        #expect(throws: DecodingError.self) {
            try decodeJSON(json, as: Choice<Category>.Answer.self)
        }
    }

    @Test func modelCardUsesReleaseDate() throws {
        let json = """
        {"name": "jev-latest", "description": "flagship", "release_date": "2026-01-01"}
        """
        let card = try decodeJSON(json, as: ModelCard.self)
        #expect(card.releaseDate == "2026-01-01")
    }
}
