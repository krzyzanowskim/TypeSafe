import Foundation
import Testing
@testable import TypeSafe

struct HTTPHeaderTests {
    @Test func lastHeaderWinsCaseInsensitive() {
        let merged = mergeHeaders([
            ["X-Custom": Optional("a"), "Accept": "text/plain"],
            ["x-custom": "b", "Accept": nil],
        ])
        #expect(merged["X-Custom"] == "b" || merged["x-custom"] == "b")
        #expect(merged.keys.contains { $0.lowercased() == "accept" } == false)
    }

    @Test func sdkHeadersProtectAuthorization() {
        let sdk = defaultSDKHeaders(apiKey: "secret", retryCount: nil)
        let merged = mergeHeaders([
            ["Authorization": Optional("Bearer leaked")],
            sdk.mapValues { Optional($0) },
        ])
        #expect(merged["Authorization"] == "Bearer secret")
        #expect(merged["User-Agent"] == "typesafe-sdk-swift/0.2.1")
        #expect(merged["X-TypeSafe-SDK"] == "typesafe-sdk-swift/0.2.1")
        #expect(merged.keys.contains { $0.lowercased() == "x-typesafe-retry-count" } == false)
    }

    @Test func retryCountHeaderOnlyOnRetries() {
        let headers = defaultSDKHeaders(apiKey: "k", retryCount: 1)
        #expect(headers["X-TypeSafe-Retry-Count"] == "1")
    }
}
