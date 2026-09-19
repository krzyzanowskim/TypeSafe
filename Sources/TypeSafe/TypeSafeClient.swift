import Foundation

public struct TypeSafeClient: Sendable {
    public let baseURL: URL
    public let defaultModel: String
    public let logLevel: LogLevel
    public let retry: RetryPolicy
    public let timeout: Duration

    public var models: Models { Models(session: session) }

    let apiKey: String
    let logger: any TypeSafeLogger
    let defaultHeaders: [String: String]
    let transport: any HTTPTransport
    let session: APISession
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
        self.session = APISession(
            baseURL: baseURL,
            apiKey: apiKey,
            defaultHeaders: defaultHeaders,
            timeout: timeout,
            retry: self.retry,
            transport: self.transport,
            random: random,
            sleep: sleep
        )
    }

    public func systemOne<Q: SystemOneQuestions>(
        state: some Encodable & Sendable,
        questions: Q,
        model: String? = nil,
        options: RequestOptions = RequestOptions()
    ) async throws -> SystemOneResult<Q.Answers> {
        let encoder = JSONEncoder()
        try requireNonEmptyQuestions(questions, encoder: encoder)

        let body = try encoder.encode(
            SystemOneRequestBody(
                state: state,
                model: model ?? defaultModel,
                questions: questions
            )
        )
        let (data, _) = try await session.request(
            method: "POST",
            path: "/v1/systemone",
            body: body,
            options: options
        )
        return try JSONDecoder().decode(SystemOneResult<Q.Answers>.self, from: data)
    }
}

private struct SystemOneRequestBody<State: Encodable, Questions: Encodable>: Encodable {
    var state: State
    var model: String
    var questions: Questions
}

private func requireNonEmptyQuestions(_ questions: some Encodable, encoder: JSONEncoder) throws {
    let data = try encoder.encode(questions)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let keys = object as? [String: Any], !keys.isEmpty else {
        throw TypeSafeError.emptyQuestions
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
