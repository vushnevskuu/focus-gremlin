import Foundation

/// Параметры llama.cpp / Ollama: меньше креативности и галлюцинаций, короткий ответ.
private enum OllamaGremlinGeneration {
    /// Низкая температура + умеренный repeat_penalty, чтобы не уходить в выдумки и не зацикливаться.
    static let temperature = 0.44
    static let topP = 0.88
    static let topK = 32
    static let repeatPenalty = 1.22
    /// Короткие реплики (до пары десятков токенов); лишнее режет `GremlinLineFormatter`.
    static let numPredict = 36
}

/// Клиент Ollama HTTP API. Всё остаётся на localhost.
struct OllamaProvider: LLMProvider {
    var baseURL: URL
    var model: String
    var urlSession: URLSession

    init(baseURL: URL, model: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlSession = urlSession
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        jpegImages: [Data],
        chatModel: String?
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let hasVision = !jpegImages.isEmpty
        request.timeoutInterval = hasVision ? 95 : 45

        let effectiveModel = chatModel.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } ?? model
        let userMessage: ChatRequest.Message
        if hasVision {
            let b64 = jpegImages.map { $0.base64EncodedString() }
            userMessage = .init(role: "user", content: userPrompt, images: b64)
        } else {
            userMessage = .init(role: "user", content: userPrompt, images: nil)
        }

        let body = ChatRequest(
            model: effectiveModel,
            messages: [
                .init(role: "system", content: systemPrompt, images: nil),
                userMessage
            ],
            stream: false,
            options: .init(
                temperature: OllamaGremlinGeneration.temperature,
                topP: OllamaGremlinGeneration.topP,
                topK: OllamaGremlinGeneration.topK,
                repeatPenalty: OllamaGremlinGeneration.repeatPenalty,
                numPredict: OllamaGremlinGeneration.numPredict,
                seed: Int.random(in: 1...999_999_999)
            )
        )
        request.httpBody = try Self.encodeJSON(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.unavailable("Некорректный ответ сервера.")
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.unavailable("Ollama HTTP \(http.statusCode): \(text.prefix(200))")
        }
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw LLMError.unavailable("Разбор JSON Ollama: \(error.localizedDescription). Фрагмент: \(snippet)")
        }
        let content = decoded.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.isEmpty {
            throw LLMError.unavailable("Пустой ответ модели (message.content).")
        }
        return content
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        return try enc.encode(value)
    }

    private struct ChatRequest: Encodable {
        var model: String
        var messages: [Message]
        var stream: Bool
        var options: Options

        struct Message: Encodable {
            var role: String
            var content: String
            var images: [String]?

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(role, forKey: .role)
                try c.encode(content, forKey: .content)
                if let images, !images.isEmpty {
                    try c.encode(images, forKey: .images)
                }
            }

            enum CodingKeys: String, CodingKey {
                case role, content, images
            }
        }

        struct Options: Encodable {
            var temperature: Double
            var topP: Double
            var topK: Int
            var repeatPenalty: Double
            var numPredict: Int
            var seed: Int
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
