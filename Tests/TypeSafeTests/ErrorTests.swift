import Testing
@testable import TypeSafe

struct ErrorTests {
    @Test func missingAPIKeyMessage() {
        #expect(
            TypeSafeError.missingAPIKey.message
                == "No API key was provided. Pass apiKey to Configuration or set the TYPESAFE_API_KEY environment variable."
        )
    }

    @Test func apiErrorPrefersErrorString() {
        let body: JSONValue = ["error": "nope"]
        #expect(APIError.message(status: 400, body: body) == "400 nope")
    }

    @Test func apiErrorPrefersErrorMessageObject() {
        let body: JSONValue = ["error": ["message": "bad key"]]
        #expect(APIError.message(status: 401, body: body) == "401 bad key")
    }

    @Test func apiErrorUsesDetailArray() {
        let body: JSONValue = [
            "detail": [
                ["loc": ["body", "questions"], "msg": "required"],
                ["loc": ["body", "model"], "msg": "missing"],
            ]
        ]
        #expect(APIError.message(status: 422, body: body) == "422 questions: required; model: missing")
    }

    @Test func apiErrorEmptyBody() {
        #expect(APIError.message(status: 500, body: nil) == "500 status code (no body)")
    }

    @Test func apiErrorTruncatesRawBody() {
        let raw = String(repeating: "a", count: 250)
        let message = APIError.message(status: 418, body: .string(raw))
        #expect(message == "418 " + String(repeating: "a", count: 200) + "…")
    }

    @Test func timeoutMessageUsesMilliseconds() {
        let error = TimeoutError(timeout: .milliseconds(10_000))
        #expect(error.errorDescription == "Request timed out after 10000ms.")
    }
}
