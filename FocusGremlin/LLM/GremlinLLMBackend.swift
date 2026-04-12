import Foundation

/// Кто выполняет вызовы `LLMProvider` для реплик гоблина (и скима страницы).
enum GremlinLLMBackend: String, CaseIterable, Codable, Sendable {
    /// Локальный Ollama (`/api/chat`).
    case ollama
    /// OpenAI Chat Completions или совместимый API (Groq, Together, Mistral, …): `POST …/v1/chat/completions`.
    case openAICompatible
    /// Anthropic Messages API: `POST https://api.anthropic.com/v1/messages`.
    case anthropic

    var settingsLabel: String {
        switch self {
        case .ollama: return "Ollama (локально)"
        case .openAICompatible: return "OpenAI / совместимый API"
        case .anthropic: return "Anthropic Claude"
        }
    }

    var successLogTag: String {
        switch self {
        case .ollama: return "Ollama"
        case .openAICompatible: return "OpenAI-совместимый API"
        case .anthropic: return "Anthropic"
        }
    }
}
