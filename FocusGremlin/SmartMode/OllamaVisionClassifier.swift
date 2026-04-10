import Foundation

/// Классификация кадра экрана через **локальную** Ollama с vision-моделью (llava, moondream и т.д.).
struct OllamaVisionClassifier: Sendable {
    var baseURL: URL
    var model: String
    var urlSession: URLSession

    func classifyScreen(jpegData: Data, language: AppLanguage) async throws -> FocusCategory {
        let b64 = jpegData.base64EncodedString()
        let instruction: String
        if language == .ru {
            instruction = """
            Ты видишь скриншот экрана пользователя. Оцени, это похоже на работу, нейтральный интерфейс или отвлечение (соцсети, видео, игры, бессмысленный скролл).
            Ответь РОВНО одним словом латиницей заглавными буквами: WORK, NEUTRAL или DISTRACT.
            """
        } else {
            instruction = """
            You see a screenshot of the user's screen. Decide if it looks like real work, neutral UI, or distraction (social, video, games, doomscrolling).
            Reply with EXACTLY one word in uppercase: WORK, NEUTRAL, or DISTRACT.
            """
        }

        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body = VisionChatRequest(
            model: model,
            messages: [
                .init(role: "user", content: instruction, images: [b64])
            ],
            stream: false,
            options: .init(temperature: 0.08, topP: 0.82, topK: 10, repeatPenalty: 1.05, numPredict: 24)
        )
        request.httpBody = try Self.encodeJSON(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.unavailable("Некорректный ответ сервера.")
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.unavailable("Ollama vision HTTP \(http.statusCode): \(text.prefix(180))")
        }
        let decoded = try JSONDecoder().decode(VisionChatResponse.self, from: data)
        let raw = decoded.message?.content ?? ""
        return Self.mapToken(from: raw)
    }

    private static func mapToken(from text: String) -> FocusCategory {
        let u = text.uppercased()
        if u.contains("DISTRACT") { return .distracting }
        if u.contains("WORK") { return .productive }
        if u.contains("NEUTRAL") { return .neutral }
        return .neutral
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        return try enc.encode(value)
    }

    private struct VisionChatRequest: Encodable {
        var model: String
        var messages: [Message]
        var stream: Bool
        var options: Options

        struct Message: Encodable {
            var role: String
            var content: String
            var images: [String]
        }

        struct Options: Encodable {
            var temperature: Double
            var topP: Double
            var topK: Int
            var repeatPenalty: Double
            var numPredict: Int
        }
    }

    private struct VisionChatResponse: Decodable {
        var message: Message?

        struct Message: Decodable {
            var role: String?
            var content: String?
        }
    }
}
