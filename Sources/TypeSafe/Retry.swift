import Foundation

public struct RetryPolicy: Sendable, Equatable {
    public var maxRetries: Int
    public var backoffInitial: Duration
    public var backoffMax: Duration
    public var backoffJitter: Double
    public var httpStatuses: Set<Int>
    public var respectRetryAfter: Bool
    public var maxRetryAfter: Duration
    public var retryConnectionErrors: Bool
    public var retryTimeouts: Bool

    public init(
        maxRetries: Int,
        backoffInitial: Duration,
        backoffMax: Duration,
        backoffJitter: Double,
        httpStatuses: Set<Int>,
        respectRetryAfter: Bool,
        maxRetryAfter: Duration,
        retryConnectionErrors: Bool,
        retryTimeouts: Bool
    ) {
        self.maxRetries = maxRetries
        self.backoffInitial = backoffInitial
        self.backoffMax = backoffMax
        self.backoffJitter = backoffJitter
        self.httpStatuses = httpStatuses
        self.respectRetryAfter = respectRetryAfter
        self.maxRetryAfter = maxRetryAfter
        self.retryConnectionErrors = retryConnectionErrors
        self.retryTimeouts = retryTimeouts
    }

    public static let `default` = RetryPolicy(
        maxRetries: 2,
        backoffInitial: .milliseconds(500),
        backoffMax: .seconds(5),
        backoffJitter: 0.25,
        httpStatuses: Set([408, 429]).union(500...599),
        respectRetryAfter: true,
        maxRetryAfter: .seconds(60),
        retryConnectionErrors: true,
        retryTimeouts: true
    )
}

public struct RetryOverride: Sendable, Equatable {
    public var maxRetries: Int?
    public var backoffInitial: Duration?
    public var backoffMax: Duration?
    public var backoffJitter: Double?
    public var httpStatuses: Set<Int>?
    public var respectRetryAfter: Bool?
    public var maxRetryAfter: Duration?
    public var retryConnectionErrors: Bool?
    public var retryTimeouts: Bool?

    public init(
        maxRetries: Int? = nil,
        backoffInitial: Duration? = nil,
        backoffMax: Duration? = nil,
        backoffJitter: Double? = nil,
        httpStatuses: Set<Int>? = nil,
        respectRetryAfter: Bool? = nil,
        maxRetryAfter: Duration? = nil,
        retryConnectionErrors: Bool? = nil,
        retryTimeouts: Bool? = nil
    ) {
        self.maxRetries = maxRetries
        self.backoffInitial = backoffInitial
        self.backoffMax = backoffMax
        self.backoffJitter = backoffJitter
        self.httpStatuses = httpStatuses
        self.respectRetryAfter = respectRetryAfter
        self.maxRetryAfter = maxRetryAfter
        self.retryConnectionErrors = retryConnectionErrors
        self.retryTimeouts = retryTimeouts
    }
}

func apply(_ override: RetryOverride?, to policy: RetryPolicy) throws -> RetryPolicy {
    guard let override else { return policy }

    var resolved = policy
    if let maxRetries = override.maxRetries {
        guard maxRetries >= 0 else {
            throw TypeSafeError(message: "`retry.maxRetries` must be a non-negative integer.")
        }
        resolved.maxRetries = maxRetries
    }
    if let backoffInitial = override.backoffInitial {
        try requireNonNegativeDuration("`retry.backoffInitial`", backoffInitial)
        resolved.backoffInitial = backoffInitial
    }
    if let backoffMax = override.backoffMax {
        try requireNonNegativeDuration("`retry.backoffMax`", backoffMax)
        resolved.backoffMax = backoffMax
    }
    if let backoffJitter = override.backoffJitter {
        guard backoffJitter.isFinite, (0...1).contains(backoffJitter) else {
            throw TypeSafeError(message: "`retry.backoffJitter` must be between 0 and 1.")
        }
        resolved.backoffJitter = backoffJitter
    }
    if let httpStatuses = override.httpStatuses {
        for status in httpStatuses {
            guard (100...999).contains(status) else {
                throw TypeSafeError(message: "`retry.httpStatuses` must contain HTTP status codes.")
            }
        }
        resolved.httpStatuses = httpStatuses
    }
    if let respectRetryAfter = override.respectRetryAfter {
        resolved.respectRetryAfter = respectRetryAfter
    }
    if let maxRetryAfter = override.maxRetryAfter {
        try requireNonNegativeDuration("`retry.maxRetryAfter`", maxRetryAfter)
        resolved.maxRetryAfter = maxRetryAfter
    }
    if let retryConnectionErrors = override.retryConnectionErrors {
        resolved.retryConnectionErrors = retryConnectionErrors
    }
    if let retryTimeouts = override.retryTimeouts {
        resolved.retryTimeouts = retryTimeouts
    }
    return resolved
}

func parseRetryAfter(retryAfterMS: String?, retryAfter: String?, now: Date) -> Duration? {
    if let retryAfterMS, let milliseconds = nonNegativeFiniteNumber(retryAfterMS) {
        return duration(milliseconds: milliseconds)
    }
    guard let retryAfter else { return nil }
    if let seconds = finiteNumber(retryAfter) {
        guard seconds >= 0 else { return nil }
        return duration(milliseconds: seconds * 1_000)
    }
    guard let date = parseHTTPDate(retryAfter) else { return nil }
    return duration(milliseconds: max(0, date.timeIntervalSince(now) * 1_000))
}

func retryDelay(
    attempt: Int,
    retryAfterMS: String?,
    retryAfter: String?,
    policy: RetryPolicy,
    random: () -> Double,
    now: Date = Date()
) -> Duration {
    if policy.respectRetryAfter,
       let retryAfter = parseRetryAfter(retryAfterMS: retryAfterMS, retryAfter: retryAfter, now: now),
       retryAfter <= policy.maxRetryAfter
    {
        return retryAfter
    }

    let exponential = min(
        milliseconds(from: policy.backoffInitial) * pow(2, Double(attempt)),
        milliseconds(from: policy.backoffMax)
    )
    return duration(milliseconds: exponential * (1 - random() * policy.backoffJitter))
}

private func requireNonNegativeDuration(_ name: String, _ duration: Duration) throws {
    guard duration >= .zero else {
        throw TypeSafeError(message: "\(name) must be a non-negative duration.")
    }
}

private func duration(milliseconds: Double) -> Duration {
    .milliseconds(Int64(milliseconds.rounded()))
}

private func milliseconds(from duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) * 1_000 + Double(attoseconds) * 1e-15
}

private func finiteNumber(_ raw: String) -> Double? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Double(trimmed), value.isFinite else { return nil }
    return value
}

private func nonNegativeFiniteNumber(_ raw: String) -> Double? {
    guard let value = finiteNumber(raw), value >= 0 else { return nil }
    return value
}

private func parseHTTPDate(_ raw: String) -> Date? {
    let formatter = DateFormatter()
    // POSIX + GMT so IMF-fixdate parsing does not depend on the host locale or zone.
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    for format in [
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
        "EEEE, dd-MMM-yy HH:mm:ss zzz",
        "EEE MMM dd HH:mm:ss yyyy",
        "EEE MMM  d HH:mm:ss yyyy",
    ] {
        formatter.dateFormat = format
        if let date = formatter.date(from: raw) {
            return date
        }
    }
    return nil
}
