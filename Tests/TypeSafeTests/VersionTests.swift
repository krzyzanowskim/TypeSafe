import Testing
@testable import TypeSafe

struct VersionTests {
    @Test func versionIs010() {
        #expect(version == "0.1.0")
    }
}
