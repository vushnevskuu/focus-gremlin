import Foundation

protocol LLMProvider: Sendable {
    func complete(systemPrompt: String, userPrompt: String) async throws -> String
}

enum LLMError: Error, LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        }
    }
}
