import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TypeSafeClient: Sendable {
    public let baseURL: URL
    public let defaultModel: String
    public let logLevel: LogLevel
    public let retry: RetryPolicy
    public let timeout: Duration
    public let compression: RequestCompression

    public var models: Models { Models(session: session) }

    let session: APISession

    public init(_ configuration: Configuration = Configuration()) throws {
        try self.init(configuration, environment: ProcessInfo.processInfo.environment)
    }

    init(
        _ configuration: Configuration,
        environment: [String: String],
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) throws {
        guard let apiKey = configuration.apiKey ?? readEnv(Env.apiKey, from: environment) else {
            throw TypeSafeError.missingAPIKey
        }

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
        self.compression = configuration.compression
        self.session = APISession(
            baseURL: baseURL,
            apiKey: apiKey,
            defaultHeaders: configuration.defaultHeaders,
            timeout: timeout,
            retry: retry,
            compression: compression,
            transport: configuration.transport ?? URLSessionTransport(),
            logger: withLevel(configuration.logger ?? StderrLogger(), level: logLevel),
            random: random,
            sleep: sleep
        )
    }

    /// Answer named questions about text, structured state, or images.
    ///
    /// - Parameters:
    ///   - state: The content to evaluate. Images in it, in question content, or in
    ///     ``TextWithAssets`` are sent under their references.
    ///   - assets: Images keyed by names you choose, for referencing them from plain strings.
    ///     Names are matched literally, so use distinct delimiters such as `<photo>`. Every
    ///     name must appear in the request.
    public func systemOne<Q: SystemOneQuestions>(
        state: some Encodable & Sendable,
        questions: Q,
        model: String? = nil,
        assets: [String: ImageAsset] = [:],
        options: RequestOptions = RequestOptions()
    ) async throws -> SystemOneResult<Q.Answers> {
        let request = try encodeRequest(
            SystemOneRequestBody(
                state: state,
                model: model ?? defaultModel,
                questions: questions
            ),
            assets: assets
        )
        try validateSystemOneBody(request.json)

        let body: RequestBody
        if request.assets.isEmpty {
            body = .json(request.json)
        } else {
            let multipart = try multipartBody(request)
            body = RequestBody(content: multipart.content, contentType: multipart.contentType, payload: multipart.payload)
        }
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

private func validateSystemOneBody(_ body: Data) throws {
    let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    guard let state = object?["state"], !(state is NSNull) else {
        throw TypeSafeError.missingState
    }
    guard let questions = object?["questions"] as? [String: Any], !questions.isEmpty else {
        throw TypeSafeError.emptyQuestions
    }
    for (name, question) in questions {
        guard let question = question as? [String: Any], question["type"] as? String == "noul" else {
            continue
        }
        let hasInstructions = question["instructions"].map { !($0 is NSNull) } ?? false
        let criteria = question["criteria"] as? [String: Any] ?? [:]
        if !hasInstructions, !criteria.values.contains(where: { !($0 is NSNull) }) {
            throw TypeSafeError.noulWithoutContent(name)
        }
    }
}

private func resolveBaseURL(_ configured: URL?, environment: [String: String]) -> URL {
    if let configured {
        return strippingTrailingSlashes(configured)
    }
    if let raw = readEnv(Env.baseURL, from: environment), let parsed = URL(string: raw) {
        return strippingTrailingSlashes(parsed)
    }
    return URL(string: "https://api.typesafe.ai")!
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
