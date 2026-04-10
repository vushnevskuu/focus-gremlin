import Foundation

/// Ключи состояний в `GremlinSpriteManifest.json` (последовательность отдельных PNG).
enum GremlinSpriteState: String, CaseIterable {
    case idle
    case talking
    /// Реплика 1–2 слова (`short_phrase` в манифесте).
    case shortPhrase = "short_phrase"
    /// Смех / хихиканье (`smile` в манифесте).
    case smile
    case final
}
