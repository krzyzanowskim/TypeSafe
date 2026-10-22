import Foundation

public struct TypeSafeError: Error, Sendable, LocalizedError, Equatable {
    public var message: String

    public var errorDescription: String? { message }

    public init(message: String) {
        self.message = message
    }

    public static let missingAPIKey = TypeSafeError(
        message: "No API key was provided. Pass apiKey to Configuration or set the TYPESAFE_API_KEY environment variable."
    )
    public static let missingState = TypeSafeError(
        message: "State is required."
    )
    public static let emptyQuestions = TypeSafeError(
        message: "At least one question is required."
    )
    public static let scoreTooFewLevels = TypeSafeError(
        message: "Score question requires at least two levels."
    )
    public static let emptyChoiceCriteria = TypeSafeError(
        message: "Choice criteria must include at least one label."
    )
    public static let unexpectedModelsPayload = TypeSafeError(
        message: "Unexpected response shape from GET /v1/models; expected { models: [...] }."
    )

    public static let emptyImage = TypeSafeError(
        message: "Image data is empty."
    )
    public static let invalidImageBase64 = TypeSafeError(
        message: "Image data must contain valid base64 text."
    )

    public static func unreferencedAssets(_ names: [String]) -> TypeSafeError {
        TypeSafeError(
            message: "Assets not referenced in the request: \(names.joined(separator: ", ")). Write each name in `assets` into `state`, question instructions, or criteria."
        )
    }

    public static func unattachedImages(_ references: [String]) -> TypeSafeError {
        TypeSafeError(
            message: "Image references without an attached image: \(references.joined(separator: ", ")). Interpolate images into a TextWithAssets or JSONValue, not a String."
        )
    }

    public static func noulWithoutContent(_ name: String) -> TypeSafeError {
        TypeSafeError(
            message: "Noul question \"\(name)\" has neither instructions nor criteria; at least one is required."
        )
    }

    public static func invalidLogLevel(_ value: String, source: String) -> TypeSafeError {
        TypeSafeError(
            message: "Invalid log level \"\(value)\" from \(source). Expected one of: debug, info, warn, error, off."
        )
    }
}

public struct APIError: Error, Sendable, LocalizedError {
    public var status: Int
    public var body: JSONValue?
    public var headers: [String: String]
    public var requestID: String?
    public var message: String
    public var retryAfter: Duration?

    public var errorDescription: String? { message }

    public init(
        status: Int,
        body: JSONValue? = nil,
        headers: [String: String] = [:],
        requestID: String? = nil,
        retryAfter: Duration? = nil
    ) {
        self.status = status
        self.body = body
        self.headers = headers
        self.requestID = requestID
        self.message = Self.message(status: status, body: body)
        self.retryAfter = retryAfter
    }

    static func message(status: Int, body: JSONValue?) -> String {
        if let body, let extracted = extractMessage(from: body), !extracted.isEmpty {
            return "\(status) \(extracted)"
        }
        guard let body else {
            return "\(status) status code (no body)"
        }
        let raw = rawString(body)
        if raw.count > 200 {
            return "\(status) \(raw.prefix(200))…"
        }
        return "\(status) \(raw)"
    }

    private static func extractMessage(from body: JSONValue) -> String? {
        guard case .object(let object) = body else { return nil }

        if case .string(let error)? = object["error"] {
            return error
        }
        if case .object(let errorObject)? = object["error"],
           case .string(let errorMessage)? = errorObject["message"] {
            return errorMessage
        }
        if case .string(let message)? = object["message"] {
            return message
        }
        if case .string(let detail)? = object["detail"] {
            return detail
        }
        if case .object(let detailObject)? = object["detail"],
           case .string(let detailMessage)? = detailObject["message"] {
            return detailMessage
        }
        if case .array(let details)? = object["detail"] {
            return describeValidationErrors(details)
        }
        return nil
    }

    private static func describeValidationErrors(_ errors: [JSONValue]) -> String? {
        let parts: [String] = errors.compactMap { error in
            guard case .object(let object) = error,
                  case .string(let msg)? = object["msg"] else {
                return nil
            }
            let loc: String
            if case .array(let items)? = object["loc"] {
                loc = items.compactMap(locSegment).joined(separator: ".")
            } else {
                loc = ""
            }
            return loc.isEmpty ? msg : "\(loc): \(msg)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private static func locSegment(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text):
            return text == "body" ? nil : text
        case .number(let number):
            if let int = Int64(exactly: number) {
                return String(int)
            }
            return String(number)
        default:
            return nil
        }
    }

    private static func rawString(_ body: JSONValue) -> String {
        switch body {
        case .string(let value):
            return value
        default:
            guard let data = try? JSONEncoder().encode(body),
                  let string = String(data: data, encoding: .utf8) else {
                return ""
            }
            return string
        }
    }
}

public struct TimeoutError: Error, Sendable, LocalizedError {
    public var timeout: Duration
    public var message: String

    public var errorDescription: String? { message }

    public init(timeout: Duration) {
        self.timeout = timeout
        self.message = "Request timed out after \(formatMilliseconds(timeout))."
    }
}

public struct ConnectionError: Error, Sendable, LocalizedError {
    public var message: String
    public var underlying: (any Error)?

    public var errorDescription: String? { message }

    public init(message: String = "Connection error.", underlying: (any Error)? = nil) {
        self.message = message
        self.underlying = underlying
    }
}

func formatMilliseconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    let milliseconds = seconds * 1000 + attoseconds / 1_000_000_000_000_000
    return "\(milliseconds)ms"
}
