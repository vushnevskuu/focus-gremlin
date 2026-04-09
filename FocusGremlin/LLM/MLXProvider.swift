import Foundation

/// Заглушка под будущий MLX / mlx-swift-LM backend без сетевых вызовов.
struct MLXProvider: LLMProvider {
    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        throw LLMError.unavailable("MLX backend ещё не подключён. Используйте Ollama или шаблоны.")
    }
}
