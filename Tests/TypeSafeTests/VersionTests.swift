import Testing
@testable import TypeSafe

struct VersionTests {
    @Test func versionIs020() {
        #expect(version == "0.2.0")
    }
}
