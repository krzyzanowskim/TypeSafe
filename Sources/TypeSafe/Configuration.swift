import Foundation

public struct Configuration: Sendable {
    public var apiKey: String?
    public var baseURL: URL?
    public var defaultModel: String?
    public var logLevel: LogLevel?
    public var logger: (any TypeSafeLogger)?
    public var retry: RetryOverride?
    public var timeout: Duration?
    public var defaultHeaders: [String: String]
    /// Request body compression. Default: ``RequestCompression/gzip`` for bodies of 1 KiB or more.
    public var compression: RequestCompression
    public var transport: (any HTTPTransport)?

    public init(
        apiKey: String? = nil,
        baseURL: URL? = nil,
        defaultModel: String? = nil,
        logLevel: LogLevel? = nil,
        logger: (any TypeSafeLogger)? = nil,
        retry: RetryOverride? = nil,
        timeout: Duration? = nil,
        defaultHeaders: [String: String] = [:],
        compression: RequestCompression = .gzip,
        transport: (any HTTPTransport)? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.logLevel = logLevel
        self.logger = logger
        self.retry = retry
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
        self.compression = compression
        self.transport = transport
    }
}

public struct RequestOptions: Sendable {
    public var timeout: Duration?
    public var retry: RetryOverride?
    public var headers: [String: String]

    public init(
        timeout: Duration? = nil,
        retry: RetryOverride? = nil,
        headers: [String: String] = [:]
    ) {
        self.timeout = timeout
        self.retry = retry
        self.headers = headers
    }
}
