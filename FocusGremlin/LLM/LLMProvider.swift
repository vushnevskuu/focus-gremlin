import Foundation

protocol LLMProvider: Sendable {
    /// `jpegImages` — кадры для мультимодального чата Ollama; `chatModel` переопределяет имя модели (обычно vision, например `llava`).
    func complete(
        systemPrompt: String,
        userPrompt: String,
        jpegImages: [Data],
        chatModel: String?
    ) async throws -> String
}

extension LLMProvider {
    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        try await complete(systemPrompt: systemPrompt, userPrompt: userPrompt, jpegImages: [], chatModel: nil)
    }
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
