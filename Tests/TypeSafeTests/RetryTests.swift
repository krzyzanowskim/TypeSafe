import Foundation
import Testing
@testable import TypeSafe

struct RetryTests {
    @Test func defaultPolicyMatchesJavaScript() {
        let policy = RetryPolicy.default
        #expect(policy.maxRetries == 2)
        #expect(policy.backoffInitial == .milliseconds(500))
        #expect(policy.backoffMax == .seconds(5))
        #expect(policy.backoffJitter == 0.25)
        #expect(policy.httpStatuses.contains(408))
        #expect(policy.httpStatuses.contains(429))
        #expect(policy.httpStatuses.contains(500))
        #expect(policy.httpStatuses.contains(599))
        #expect(!policy.httpStatuses.contains(499))
        #expect(policy.respectRetryAfter)
        #expect(policy.maxRetryAfter == .seconds(60))
        #expect(policy.retryConnectionErrors)
        #expect(policy.retryTimeouts)
    }

    @Test func exponentialBackoffWithNoJitter() {
        let policy = try! apply(
            RetryOverride(backoffJitter: 0),
            to: .default
        )
        #expect(retryDelay(attempt: 0, retryAfterMS: nil, retryAfter: nil, policy: policy, random: { 0 }) == .milliseconds(500))
        #expect(retryDelay(attempt: 1, retryAfterMS: nil, retryAfter: nil, policy: policy, random: { 0 }) == .milliseconds(1000))
        #expect(retryDelay(attempt: 2, retryAfterMS: nil, retryAfter: nil, policy: policy, random: { 0 }) == .milliseconds(2000))
        #expect(retryDelay(attempt: 10, retryAfterMS: nil, retryAfter: nil, policy: policy, random: { 0 }) == .seconds(5))
    }

    @Test func jitterUsesRandom() {
        let policy = RetryPolicy.default
        let delay = retryDelay(attempt: 0, retryAfterMS: nil, retryAfter: nil, policy: policy, random: { 1 })
        #expect(delay == .milliseconds(375))
    }

    @Test func retryAfterMSWinsWhenUnderCap() {
        let delay = retryDelay(
            attempt: 0,
            retryAfterMS: "250",
            retryAfter: "10",
            policy: .default,
            random: { 0 }
        )
        #expect(delay == .milliseconds(250))
    }

    @Test func retryAfterHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let date = "Thu, 01 Jan 1970 00:16:45 GMT"
        let delay = parseRetryAfter(retryAfterMS: nil, retryAfter: date, now: now)
        #expect(delay == .seconds(5))
    }

    @Test func retryAfterAboveCapFallsBackToBackoff() {
        let delay = retryDelay(
            attempt: 0,
            retryAfterMS: "120000",
            retryAfter: nil,
            policy: .default,
            random: { 0 }
        )
        #expect(delay == .milliseconds(500))
    }

    @Test func oversizedRetryAfterMSFallsBackToBackoff() {
        let delay = retryDelay(
            attempt: 0,
            retryAfterMS: "1e20",
            retryAfter: nil,
            policy: .default,
            random: { 0 }
        )
        #expect(delay == .milliseconds(500))
    }

    @Test func overrideReplacesSingleField() throws {
        let policy = try apply(RetryOverride(maxRetries: 0), to: .default)
        #expect(policy.maxRetries == 0)
        #expect(policy.backoffInitial == .milliseconds(500))
    }
}
