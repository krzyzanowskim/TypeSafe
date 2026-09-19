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
        #expect(APIError(status: 400, body: body).message == "400 nope")
    }

    @Test func apiErrorPrefersErrorMessageObject() {
        let body: JSONValue = ["error": ["message": "bad key"]]
        #expect(APIError(status: 401, body: body).message == "401 bad key")
    }

    @Test func apiErrorUsesDetailArray() {
        let body: JSONValue = [
            "detail": [
                ["loc": ["body", "questions"], "msg": "required"],
                ["loc": ["body", "model"], "msg": "missing"],
            ]
        ]
        #expect(APIError(status: 422, body: body).message == "422 questions: required; model: missing")
    }

    @Test func apiErrorEmptyBody() {
        #expect(APIError(status: 500, body: nil).message == "500 status code (no body)")
    }

    @Test func apiErrorTruncatesRawBody() {
        let raw = String(repeating: "a", count: 250)
        let message = APIError(status: 418, body: .string(raw)).message
        #expect(message == "418 " + String(repeating: "a", count: 200) + "…")
    }

    @Test func timeoutMessageUsesMilliseconds() {
        let error = TimeoutError(timeout: .milliseconds(10_000))
        #expect(error.errorDescription == "Request timed out after 10000ms.")
    }
}
