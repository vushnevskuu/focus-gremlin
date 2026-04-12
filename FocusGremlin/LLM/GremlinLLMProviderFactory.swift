import Foundation

enum GremlinLLMProviderFactory {
    /// Собирает провайдера по настройкам. При ошибке конфигурации — `MockLLMProvider` с пояснением.
    @MainActor
    static func makeProvider(settings: SettingsStore) -> any LLMProvider {
        switch settings.llmBackend {
        case .ollama:
            let raw = settings.ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw), url.scheme != nil else {
                return MockLLMProvider(cannedResponse: "Ollama: проверь базовый URL в настройках.")
            }
            return OllamaProvider(baseURL: url, model: settings.ollamaModel)

        case .openAICompatible:
            let baseRaw = settings.cloudAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: baseRaw), url.scheme != nil else {
                return MockLLMProvider(cannedResponse: "Облако: укажите базовый URL API (например https://api.openai.com/v1).")
            }
            let key = SecureLLMAPIKey.read(slot: .openAICompatible) ?? ""
            return OpenAICompatibleProvider(
                baseURL: url,
                apiKey: key,
                defaultModel: settings.cloudChatModel
            )

        case .anthropic:
            let key = SecureLLMAPIKey.read(slot: .anthropic) ?? ""
            return AnthropicMessagesProvider(apiKey: key, defaultModel: settings.cloudChatModel)
        }
    }
}
