import Foundation

/// Клиент Ollama HTTP API. Всё остаётся на localhost.
struct OllamaProvider: LLMProvider {
    var baseURL: URL
    var model: String
    var urlSession: URLSession

    init(baseURL: URL, model: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.urlSession = urlSession
    }

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.unavailable("Некорректный ответ сервера.")
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.unavailable("Ollama HTTP \(http.statusCode): \(text.prefix(200))")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.isEmpty {
            throw LLMError.unavailable("Пустой ответ модели.")
        }
        return content
    }

    private struct ChatRequest: Encodable {
        var model: String
        var messages: [Message]
        var stream: Bool

        struct Message: Encodable {
            var role: String
            var content: String
        }
    }

    private struct ChatResponse: Decodable {
        var message: Message?

        struct Message: Decodable {
            var role: String?
            var content: String?
        }
    }
}
