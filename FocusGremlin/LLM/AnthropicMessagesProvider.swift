import Foundation

/// Клиент Anthropic Messages API (vision + текст).
struct AnthropicMessagesProvider: LLMProvider {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var apiKey: String
    var defaultModel: String
    var urlSession: URLSession

    init(apiKey: String, defaultModel: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.defaultModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlSession = urlSession
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        jpegImages: [Data],
        chatModel: String?
    ) async throws -> String {
        let model = chatModel.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel
        guard !model.isEmpty else {
            throw LLMError.unavailable("Имя модели пустое.")
        }
        guard !apiKey.isEmpty else {
            throw LLMError.unavailable("Нет API-ключа Anthropic: введите в настройках и «Сохранить ключ».")
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = jpegImages.isEmpty ? 60 : 120

        var userBlocks: [[String: Any]] = []
        for data in jpegImages {
            userBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": data.base64EncodedString()
                ]
            ])
        }
        userBlocks.append([
            "type": "text",
            "text": userPrompt
        ])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 180,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userBlocks]
            ],
            "temperature": 0.44
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.unavailable("Некорректный ответ сервера.")
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.unavailable("Anthropic HTTP \(http.statusCode): \(text.prefix(280))")
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let text = decoded.content?
            .first { $0.type == "text" }?
            .text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw LLMError.unavailable("Пустой ответ Anthropic (нет text-блока).")
        }
        return text
    }

    private struct AnthropicResponse: Decodable {
        var content: [Block]?
        struct Block: Decodable {
            var type: String?
            var text: String?
        }
    }
}
