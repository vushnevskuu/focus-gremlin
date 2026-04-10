import Foundation

struct MockLLMProvider: LLMProvider {
    var cannedResponse: String

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
        return cannedResponse
    }
}
