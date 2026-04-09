import Foundation

struct MockLLMProvider: LLMProvider {
    var cannedResponse: String

    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        cannedResponse
    }
}
