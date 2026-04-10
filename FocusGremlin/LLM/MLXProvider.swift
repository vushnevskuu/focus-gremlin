import Foundation

/// Заглушка под будущий MLX / mlx-swift-LM backend без сетевых вызовов.
struct MLXProvider: LLMProvider {
    func complete(
        systemPrompt: String,
        userPrompt: String,
        jpegImages: [Data],
        chatModel: String?
    ) async throws -> String {
        _ = systemPrompt
        _ = userPrompt
        _ = jpegImages
        _ = chatModel
        throw LLMError.unavailable("MLX backend ещё не подключён. Используйте Ollama или шаблоны.")
    }
}
