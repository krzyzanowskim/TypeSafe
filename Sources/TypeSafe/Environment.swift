import Foundation

enum Env {
    static let apiKey = "TYPESAFE_API_KEY"
    static let baseURL = "TYPESAFE_BASE_URL"
    static let defaultModel = "TYPESAFE_DEFAULT_MODEL"
    static let logLevel = "TYPESAFE_LOG_LEVEL"
}

func readEnv(_ name: String, from environment: [String: String]) -> String? {
    guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty
    else {
        return nil
    }
    return value
}
