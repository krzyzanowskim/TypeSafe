import Foundation
import Testing
@testable import TypeSafe

enum Category: String, CaseIterable, Sendable, ChoiceLabel {
    case billing, technical, other
}

struct QuestionTests {
    @Test func noulEncodesTypeAndNullInstructions() throws {
        let json = try #require(encodeJSON(Noul("Is this billing?")) as? [String: Any])
        #expect(json["type"] as? String == "noul")
        #expect(json["instructions"] as? String == "Is this billing?")
        #expect(json["criteria"] == nil)
    }

    @Test func noulEncodesYesNoAsTrueFalse() throws {
        let json = try #require(
            encodeJSON(Noul("urgent?", yes: "time-sensitive", no: "not urgent")) as? [String: Any]
        )
        let criteria = try #require(json["criteria"] as? [String: Any])
        #expect(criteria["true"] as? String == "time-sensitive")
        #expect(criteria["false"] as? String == "not urgent")
    }

    @Test func choiceEnumFillsAllCases() throws {
        let json = try #require(encodeJSON(Choice<Category>("What is this about?")) as? [String: Any])
        #expect(json["type"] as? String == "choice")
        let criteria = try #require(json["criteria"] as? [String: Any])
        #expect(criteria["billing"] is NSNull)
        #expect(criteria["technical"] is NSNull)
        #expect(criteria["other"] is NSNull)
    }

    @Test func choiceKeepsNullDescriptions() throws {
        let question = Choice<Category>(
            "What is this about?",
            criteria: [.billing: "money", .technical: nil, .other: nil]
        )
        let json = try #require(encodeJSON(question) as? [String: Any])
        let criteria = try #require(json["criteria"] as? [String: Any])
        #expect(criteria["billing"] as? String == "money")
        #expect(criteria["technical"] is NSNull)
    }

    @Test func choiceStringRequiresLabels() throws {
        let error = try #require(throws: TypeSafeError.self) {
            try Choice<String>("What is this about?")
        }
        #expect(error == .emptyChoiceCriteria)
    }

    @Test func scoreEncodesArrayAndRejectsOneLevel() throws {
        let json = try #require(
            encodeJSON(try Score("How urgent?", levels: ["can wait", "today"])) as? [String: Any]
        )
        #expect(json["type"] as? String == "score")
        #expect(json["criteria"] as? [String] == ["can wait", "today"])

        let error = try #require(throws: TypeSafeError.self) {
            try Score("How urgent?", levels: ["only"])
        }
        #expect(error == .scoreTooFewLevels)
    }
}
