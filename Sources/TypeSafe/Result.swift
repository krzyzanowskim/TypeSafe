public struct Usage: Decodable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

public struct SystemOneResult<Answers: Decodable & Sendable>: Decodable, Sendable {
    public var model: String
    public var answers: Answers
    public var usage: Usage
}

public struct ModelCard: Decodable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var releaseDate: String

    enum CodingKeys: String, CodingKey {
        case name, description
        case releaseDate = "release_date"
    }
}
