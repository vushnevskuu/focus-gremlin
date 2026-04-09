import Foundation

/// Слияние rule-based класса с результатом локального vision (Ollama VLM). Чистая логика для тестов.
enum SmartCategoryMerge {
    /// Vision может усилить отвлечение или смягчить ложное срабатывание по bundle/title.
    static func merge(rule: FocusCategory, vision: FocusCategory?) -> FocusCategory {
        guard let v = vision else { return rule }
        switch (rule, v) {
        case (.productive, .distracting):
            return .distracting
        case (.neutral, .distracting):
            return .distracting
        case (.neutral, .productive):
            return .productive
        case (.distracting, .productive):
            return .neutral
        case (.productive, .productive), (.productive, .neutral):
            return rule
        case (.distracting, .distracting), (.distracting, .neutral):
            return rule
        case (.neutral, .neutral):
            return rule
        }
    }
}
