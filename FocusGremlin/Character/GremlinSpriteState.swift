import Foundation

/// Ключи состояний в `GremlinSpriteManifest.json` (последовательность отдельных PNG).
enum GremlinSpriteState: String, CaseIterable {
    case idle
    case talking
    case final
}
