public protocol SystemOneQuestions: Encodable, Sendable {
    associatedtype Answers: Decodable & Sendable
}

public protocol ChoiceLabel: Hashable, Sendable {
    init?(rawValue: String)
    var rawValue: String { get }
}

extension String: ChoiceLabel {
    // Empty conformance is ambiguous: String has many String-taking inits and is not RawRepresentable.
    public init?(rawValue: String) { self = rawValue }
    public var rawValue: String { self }
}

// String-backed enums already witness the requirements via RawRepresentable.
extension ChoiceLabel where Self: RawRepresentable, RawValue == String {}

public struct Noul: Encodable, Sendable {
    public var instructions: JSONValue?
    public var criteria: Criteria?

    public struct Criteria: Encodable, Sendable {
        public var yes: JSONValue?
        public var no: JSONValue?

        public init(yes: JSONValue? = nil, no: JSONValue? = nil) {
            self.yes = yes
            self.no = no
        }

        enum CodingKeys: String, CodingKey {
            case yes = "true"
            case no = "false"
        }
    }

    public struct Answer: Decodable, Sendable, Equatable {
        public var noul: Double
    }

    public init(_ instructions: String, yes: JSONValue? = nil, no: JSONValue? = nil) {
        self.init(.string(instructions), criteria: Criteria(yes: yes, no: no))
    }

    public init(_ instructions: JSONValue?, criteria: Criteria? = nil) {
        self.instructions = instructions
        if let criteria, criteria.yes != nil || criteria.no != nil {
            self.criteria = criteria
        } else {
            self.criteria = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("noul", forKey: .type)
        try container.encode(instructions ?? .null, forKey: .instructions)
        try container.encodeIfPresent(criteria, forKey: .criteria)
    }

    enum CodingKeys: String, CodingKey {
        case type, instructions, criteria
    }
}

public struct Choice<Label: ChoiceLabel>: Encodable, Sendable {
    public var instructions: JSONValue?
    public var criteria: [Label: JSONValue?]

    public struct Answer: Decodable, Sendable, Equatable {
        public var choice: Label
        public var confidence: Double
        public var probabilities: [Label: Double]

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            choice = try Self.decodeLabel(
                try container.decode(String.self, forKey: .choice),
                in: container,
                forKey: .choice
            )
            confidence = try container.decode(Double.self, forKey: .confidence)
            let rawProbabilities = try container.decode([String: Double].self, forKey: .probabilities)
            var decoded: [Label: Double] = [:]
            decoded.reserveCapacity(rawProbabilities.count)
            for (raw, value) in rawProbabilities {
                decoded[try Self.decodeLabel(raw, in: container, forKey: .probabilities)] = value
            }
            probabilities = decoded
        }

        private static func decodeLabel(
            _ raw: String,
            in container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> Label {
            guard let label = Label(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Unknown choice label \(raw)"
                )
            }
            return label
        }

        enum CodingKeys: String, CodingKey {
            case choice, confidence, probabilities
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("choice", forKey: .type)
        try container.encode(instructions ?? .null, forKey: .instructions)
        let encodedCriteria = Dictionary(uniqueKeysWithValues: criteria.map { ($0.key.rawValue, $0.value ?? .null) })
        try container.encode(encodedCriteria, forKey: .criteria)
    }

    enum CodingKeys: String, CodingKey {
        case type, instructions, criteria
    }
}

extension Choice {
    public init(_ instructions: String, criteria: [Label: JSONValue?] = [:]) throws {
        try self.init(.string(instructions), criteria: criteria)
    }

    public init(_ instructions: JSONValue?, criteria: [Label: JSONValue?] = [:]) throws {
        guard !criteria.isEmpty else {
            throw TypeSafeError.emptyChoiceCriteria
        }
        self.instructions = instructions
        self.criteria = criteria
    }
}

extension Choice where Label: CaseIterable {
    public init(_ instructions: String, criteria: [Label: JSONValue?] = [:]) {
        self.init(.string(instructions), criteria: criteria)
    }

    public init(_ instructions: JSONValue?, criteria: [Label: JSONValue?] = [:]) {
        self.instructions = instructions
        if criteria.isEmpty {
            self.criteria = Dictionary(uniqueKeysWithValues: Label.allCases.map { ($0, nil) })
        } else {
            self.criteria = criteria
        }
    }
}

public struct Score: Encodable, Sendable {
    public var instructions: JSONValue?
    public var criteria: [JSONValue?]

    public struct Answer: Decodable, Sendable, Equatable {
        public var score: Double
        public var confidence: Double
        public var legend: [String: JSONValue?]
        public var probabilities: [String: Double]
    }

    public init(_ instructions: String, levels: [String]) throws {
        try self.init(.string(instructions), levels: levels.map { .string($0) })
    }

    public init(_ instructions: String, levels: [JSONValue?]) throws {
        try self.init(.string(instructions), levels: levels)
    }

    public init(_ instructions: JSONValue?, levels: [JSONValue?]) throws {
        guard levels.count >= 2 else {
            throw TypeSafeError.scoreTooFewLevels
        }
        self.instructions = instructions
        self.criteria = levels
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("score", forKey: .type)
        try container.encode(instructions ?? .null, forKey: .instructions)
        try container.encode(criteria.map { $0 ?? .null }, forKey: .criteria)
    }

    enum CodingKeys: String, CodingKey {
        case type, instructions, criteria
    }
}
