import Foundation

/// Клиент `POST {baseURL}/chat/completions` в формате OpenAI (в т.ч. Groq, Together, локальные прокси).
struct OpenAICompatibleProvider: LLMProvider {
    var baseURL: URL
    var apiKey: String
    var defaultModel: String
    var urlSession: URLSession

    init(baseURL: URL, apiKey: String, defaultModel: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
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
            throw LLMError.unavailable("Нет API-ключа: введите ключ в настройках и нажмите «Сохранить ключ».")
        }

        let url = Self.chatCompletionsURL(from: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = jpegImages.isEmpty ? 60 : 120

        let userContent: Any = {
            guard !jpegImages.isEmpty else { return userPrompt }
            var parts: [[String: Any]] = [["type": "text", "text": userPrompt]]
            for data in jpegImages {
                let b64 = data.base64EncodedString()
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(b64)"]
                ])
            }
            return parts
        }()

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.44,
            "max_tokens": 180
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.unavailable("Некорректный ответ сервера.")
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            let detail = Self.humanReadableOpenAIHTTPError(status: http.statusCode, body: text)
            throw LLMError.unavailable(detail)
        }

        let decoded: OpenAIChatResponse
        do {
            decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        } catch {
            let frag = String(data: data, encoding: .utf8).map { String($0.prefix(500)) } ?? ""
            throw LLMError.unavailable("Ответ API не распознан: \(error.localizedDescription). Фрагмент: \(frag)")
        }
        let msg = decoded.choices?.first?.message
        let content = (msg?.resolvedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty { return content }
        let refusal = (msg?.refusal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !refusal.isEmpty {
            throw LLMError.unavailable("Модель не вернула текст (refusal): \(String(refusal.prefix(240)))")
        }
        throw LLMError.unavailable("Пустой ответ: в choices[0].message нет текста.")
    }

    /// `…/v1` + `chat/completions`. Подправляет типичный ввод `https://api.openai.com` без `/v1`.
    private static func chatCompletionsURL(from base: URL) -> URL {
        var trimmed = base.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard var parts = URLComponents(string: trimmed) else {
            return base.appendingPathComponent("chat/completions")
        }
        let host = parts.host?.lowercased() ?? ""
        let pathTrim = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if host == "api.openai.com", pathTrim.isEmpty {
            parts.path = "/v1"
        }
        guard let root = parts.url else {
            return base.appendingPathComponent("chat/completions")
        }
        return root.appendingPathComponent("chat/completions")
    }

    /// Укорачивает типичные JSON-ошибки OpenAI до понятной строки для строки диагностики в настройках.
    private static func humanReadableOpenAIHTTPError(status: Int, body: String) -> String {
        let raw = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Срабатывает даже если структура JSON чуть отличается от Decodable.
        if raw.localizedCaseInsensitiveContains("billing_not_active") {
            return "HTTP \(status): OpenAI — не активен биллинг у аккаунта этого ключа (см. platform.openai.com/account/billing)."
        }
        if raw.localizedCaseInsensitiveContains("insufficient_quota") {
            return "HTTP \(status): OpenAI — исчерпана квота или лимит; проверьте биллинг и лимиты."
        }
        if let decoded = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: Data(body.utf8)),
           let e = decoded.error {
            let code = e.code ?? ""
            let typ = e.type ?? ""
            if code == "billing_not_active" || typ == "billing_not_active" {
                return "HTTP \(status): аккаунт без активной оплаты — на сайте провайдера (Billing) пополните баланс или привяжите способ оплаты."
            }
            if let m = e.message?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty, m.count <= 220 {
                return "HTTP \(status): \(m)"
            }
        }
        let tail = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.count > 240 {
            return "HTTP \(status): \(tail.prefix(240))…"
        }
        return "HTTP \(status): \(tail)"
    }

    private struct OpenAIAPIErrorEnvelope: Decodable {
        struct Err: Decodable {
            var message: String?
            var type: String?
            var code: String?
        }
        var error: Err?
    }

    private struct OpenAIChatResponse: Decodable {
        var choices: [Choice]?
        struct Choice: Decodable {
            var message: Message?
        }
        struct Message: Decodable {
            var refusal: String?
            /// Текст из `content`: строка или массив блоков `{type,text}` (встречается у части совместимых API).
            var resolvedText: String

            private enum CodingKeys: String, CodingKey {
                case content
                case refusal
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                refusal = try c.decodeIfPresent(String.self, forKey: .refusal)
                if let s = try? c.decode(String.self, forKey: .content) {
                    resolvedText = s
                } else if let blocks = try? c.decode([ContentBlock].self, forKey: .content) {
                    resolvedText = blocks.compactMap(\.text).joined(separator: "\n")
                } else {
                    resolvedText = ""
                }
            }

            struct ContentBlock: Decodable {
                var type: String?
                var text: String?
            }
        }
    }
}
