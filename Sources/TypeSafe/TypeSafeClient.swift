import Foundation

public struct TypeSafeClient: Sendable {
    public let baseURL: URL
    public let defaultModel: String
    public let logLevel: LogLevel
    public let retry: RetryPolicy
    public let timeout: Duration

    let apiKey: String
    let logger: any TypeSafeLogger
    let defaultHeaders: [String: String]
    let transport: any HTTPTransport
    let random: @Sendable () -> Double
    let sleep: @Sendable (Duration) async throws -> Void

    public init(_ configuration: Configuration = Configuration()) throws {
        try self.init(configuration, environment: ProcessInfo.processInfo.environment)
    }

    init(
        _ configuration: Configuration,
        environment: [String: String],
        transport: (any HTTPTransport)? = nil,
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) throws {
        guard let apiKey = configuration.apiKey ?? readEnv(Env.apiKey, from: environment) else {
            throw TypeSafeError.missingAPIKey
        }
        self.apiKey = apiKey

        self.baseURL = resolveBaseURL(configuration.baseURL, environment: environment)
        self.defaultModel =
            configuration.defaultModel
            ?? readEnv(Env.defaultModel, from: environment)
            ?? "jev-latest"
        self.logLevel = try resolveLogLevel(configuration.logLevel, environment: environment)

        let timeout = configuration.timeout ?? .seconds(10)
        guard timeout > .zero else {
            throw TypeSafeError(message: "timeout must be a positive duration.")
        }
        self.timeout = timeout

        self.retry = try apply(configuration.retry, to: .default)
        self.logger = withLevel(configuration.logger ?? StderrLogger(), level: logLevel)
        self.defaultHeaders = configuration.defaultHeaders
        self.transport = configuration.transport ?? transport ?? URLSessionTransport()
        self.random = random
        self.sleep = sleep
    }
}

private func resolveBaseURL(_ configured: URL?, environment: [String: String]) -> URL {
    let fallback = URL(string: "https://api.typesafe.ai")!
    let url: URL
    if let configured {
        url = configured
    } else if let raw = readEnv(Env.baseURL, from: environment), let parsed = URL(string: raw) {
        url = parsed
    } else {
        url = fallback
    }
    return strippingTrailingSlashes(url)
}

private func resolveLogLevel(_ configured: LogLevel?, environment: [String: String]) throws -> LogLevel {
    if let configured {
        return configured
    }
    if let raw = readEnv(Env.logLevel, from: environment) {
        return try parseLogLevel(raw, source: Env.logLevel)
    }
    return .warn
}

private func strippingTrailingSlashes(_ url: URL) -> URL {
    var string = url.absoluteString
    while string.hasSuffix("/") {
        string.removeLast()
    }
    return URL(string: string) ?? url
}
