import Testing
@testable import TypeSafe

final class RecordingLogger: TypeSafeLogger, @unchecked Sendable {
    struct Line: Equatable {
        var level: String
        var message: String
    }

    var lines: [Line] = []

    func debug(_ message: String) { lines.append(Line(level: "debug", message: message)) }
    func info(_ message: String) { lines.append(Line(level: "info", message: message)) }
    func warn(_ message: String) { lines.append(Line(level: "warn", message: message)) }
    func error(_ message: String) { lines.append(Line(level: "error", message: message)) }
}

struct LoggingTests {
    @Test func warnDropsDebugAndInfo() {
        let sink = RecordingLogger()
        let logger = withLevel(sink, level: .warn)
        logger.debug("d")
        logger.info("i")
        logger.warn("w")
        logger.error("e")
        #expect(sink.lines == [
            .init(level: "warn", message: "w"),
            .init(level: "error", message: "e"),
        ])
    }

    @Test func offDropsAll() {
        let sink = RecordingLogger()
        let logger = withLevel(sink, level: .off)
        logger.error("e")
        #expect(sink.lines.isEmpty)
    }

    @Test func parseLogLevelRejectsUnknown() throws {
        let error = try #require(throws: TypeSafeError.self) {
            try parseLogLevel("verbose", source: "TYPESAFE_LOG_LEVEL")
        }
        #expect(
            error.message
                == "Invalid log level \"verbose\" from TYPESAFE_LOG_LEVEL. Expected one of: debug, info, warn, error, off."
        )
    }

    @Test func redactsBearerTokenKeepingTail() {
        let redacted = redactHeaders([
            "Authorization": "Bearer abcdefghijklmnop",
            "X-Api-Key": "abcdefghijklmnop",
            "Cookie": "session=secret",
            "Accept": "application/json",
        ])
        #expect(redacted["Authorization"] == "Bearer ***mnop")
        #expect(redacted["X-Api-Key"] == "***mnop")
        #expect(redacted["Cookie"] == "***")
        #expect(redacted["Accept"] == "application/json")
    }

    @Test func redactsShortSecretsWithoutTail() {
        let redacted = redactHeaders(["x-api-key": "short"])
        #expect(redacted["x-api-key"] == "***")
    }
}
