import Foundation

public enum LogLevel: String, Sendable, CaseIterable {
    case debug
    case info
    case warn
    case error
    case off
}

public protocol TypeSafeLogger: Sendable {
    func debug(_ message: String)
    func info(_ message: String)
    func warn(_ message: String)
    func error(_ message: String)
}

func parseLogLevel(_ value: String, source: String) throws -> LogLevel {
    guard let level = LogLevel(rawValue: value) else {
        throw TypeSafeError.invalidLogLevel(value, source: source)
    }
    return level
}

func withLevel(_ sink: any TypeSafeLogger, level: LogLevel) -> any TypeSafeLogger {
    FilteredLogger(sink: sink, level: level)
}

func redactHeaders(_ headers: [String: String]) -> [String: String] {
    var redacted: [String: String] = [:]
    redacted.reserveCapacity(headers.count)
    for (name, value) in headers {
        switch name.lowercased() {
        case "cookie", "set-cookie":
            redacted[name] = "***"
        case "authorization", "proxy-authorization", "x-api-key":
            redacted[name] = redactSecret(value)
        default:
            redacted[name] = value
        }
    }
    return redacted
}

struct StderrLogger: TypeSafeLogger {
    func debug(_ message: String) { write(message) }
    func info(_ message: String) { write(message) }
    func warn(_ message: String) { write(message) }
    func error(_ message: String) { write(message) }

    private func write(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("[typesafe-sdk] \(message)\n".utf8))
    }
}

private struct FilteredLogger: TypeSafeLogger {
    let sink: any TypeSafeLogger
    let level: LogLevel

    func debug(_ message: String) { emit(.debug, message, sink.debug) }
    func info(_ message: String) { emit(.info, message, sink.info) }
    func warn(_ message: String) { emit(.warn, message, sink.warn) }
    func error(_ message: String) { emit(.error, message, sink.error) }

    private func emit(_ messageLevel: LogLevel, _ message: String, _ write: (String) -> Void) {
        if messageLevel.rank >= level.rank {
            write(message)
        }
    }
}

extension LogLevel {
    /// Higher numbers are more severe; `off` is above every emit-able level.
    var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warn: 2
        case .error: 3
        case .off: 4
        }
    }
}

/// Masks a secret, keeping the last four characters of values longer than eight.
/// When the value contains a space, the scheme prefix (e.g. `"Bearer "`) is preserved.
private func redactSecret(_ value: String) -> String {
    if let space = value.firstIndex(of: " ") {
        let scheme = value[...space]
        let secret = value[value.index(after: space)...]
        return String(scheme) + mask(String(secret))
    }
    return mask(value)
}

private func mask(_ secret: String) -> String {
    if secret.count > 8 {
        return "***" + secret.suffix(4)
    }
    return "***"
}
