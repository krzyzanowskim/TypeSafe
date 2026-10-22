import Testing
@testable import TypeSafe

struct VersionTests {
    @Test func versionIs021() {
        #expect(version == "0.2.1")
    }
}
