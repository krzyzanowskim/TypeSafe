import Foundation
import Testing
@testable import TypeSafe

struct ConfigurationTests {
    @Test func missingAPIKeyThrows() throws {
        let error = try #require(throws: TypeSafeError.self) {
            try TypeSafeClient(Configuration(), environment: [:])
        }
        #expect(error == .missingAPIKey)
    }

    @Test func explicitAPIKeyBeatsEnv() throws {
        let client = try TypeSafeClient(
            Configuration(apiKey: "from-code"),
            environment: [Env.apiKey: "from-env"]
        )
        #expect(client.session.apiKey == "from-code")
    }

    @Test func envAPIKeyUsedWhenCodeOmits() throws {
        let client = try TypeSafeClient(
            Configuration(),
            environment: [Env.apiKey: "  env-key  "]
        )
        #expect(client.session.apiKey == "env-key")
    }

    @Test func blankEnvIsIgnored() throws {
        let error = try #require(throws: TypeSafeError.self) {
            try TypeSafeClient(Configuration(), environment: [Env.apiKey: "   "])
        }
        #expect(error == .missingAPIKey)
    }

    @Test func stripsTrailingSlashesAndAppliesDefaults() throws {
        let client = try TypeSafeClient(
            Configuration(apiKey: "k", baseURL: URL(string: "https://example.com///")),
            environment: [:]
        )
        #expect(client.baseURL.absoluteString == "https://example.com")
        #expect(client.defaultModel == "jev-latest")
        #expect(client.logLevel == .warn)
        #expect(client.timeout == .seconds(10))
        #expect(client.retry == .default)
    }

    @Test func envOverridesDefaults() throws {
        let client = try TypeSafeClient(
            Configuration(),
            environment: [
                Env.apiKey: "k",
                Env.baseURL: "https://other.example/",
                Env.defaultModel: "jev-1",
                Env.logLevel: "debug",
            ]
        )
        #expect(client.baseURL.absoluteString == "https://other.example")
        #expect(client.defaultModel == "jev-1")
        #expect(client.logLevel == .debug)
    }

    @Test func rejectsNonPositiveTimeout() throws {
        let error = try #require(throws: TypeSafeError.self) {
            try TypeSafeClient(
                Configuration(apiKey: "k", timeout: .zero),
                environment: [:]
            )
        }
        #expect(error.message == "timeout must be a positive duration.")
    }
}
