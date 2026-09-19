import TypeSafe

@main
struct Demo {
    static func main() async throws {
        do {
            try await run()
        } catch let error as APIError {
            let requestID = error.requestID ?? "unknown"
            print("API error \(error.status) (request \(requestID)): \(String(describing: error.body))")
        }
    }

    private static func run() async throws {
        let client = try TypeSafeClient()

        let models = try await client.models.list()
        print("Available models:", models.map(\.name).joined(separator: ", "))

        struct Ticket: Encodable {
            var subject: String
            var body: String
        }

        enum Tone: String, CaseIterable, Sendable, ChoiceLabel {
            case calm, frustrated, angry
        }

        struct TicketQuestions: SystemOneQuestions {
            var isBilling = Noul("Is this ticket about billing?")
            var sentiment = Choice<Tone>("What is the customer's tone?")
            var urgency = try! Score(
                "How urgent is this ticket?",
                levels: ["can wait", "this week", "today", "right now"]
            )
            var refundRisk = try! Score(
                "How likely is the customer to demand a refund?",
                levels: ["unlikely", "possible", "likely"]
            )

            struct Answers: Decodable, Sendable {
                var isBilling: Noul.Answer
                var sentiment: Choice<Tone>.Answer
                var urgency: Score.Answer
                var refundRisk: Score.Answer
            }
        }

        let ticket = Ticket(
            subject: "Charged twice this month",
            body: "Hi, I see two charges of $49 on my card for August. I only have one account. Please fix this ASAP, I'm pretty frustrated."
        )

        let result = try await client.systemOne(state: ticket, questions: TicketQuestions())
        let answers = result.answers
        print("billing?    ", answers.isBilling.noul)
        print(
            "tone        ",
            answers.sentiment.choice.rawValue,
            "(\(answers.sentiment.confidence))"
        )
        print("urgency     ", answers.urgency.score)
        print(
            "refund risk ",
            answers.refundRisk.score,
            "(\(answers.refundRisk.confidence) confidence)"
        )
        print("tokens      ", result.usage.inputTokens, "in /", result.usage.outputTokens, "out")
    }
}
