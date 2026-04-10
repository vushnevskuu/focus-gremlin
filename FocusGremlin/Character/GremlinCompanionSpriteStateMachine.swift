import Foundation

// MARK: - Жизненный цикл (нативный оверлей macOS)

/// Состояние «сессии» визуала компаньона. Аналог «вкладки с doomscroll» — пока `distracting`, гоблин закреплён; после `final` сценарий завершён.
enum GremlinCompanionLifecycleState: Equatable, Sendable {
    /// Можно показывать гоблина во время отвлечения и доставки реплик.
    case active
    /// Сразу после `final` в продуктивном контексте: оверлей скрыт до следующего `distracting` (новый doomscroll снова включает `.active`).
    case terminal
}

// MARK: - Роли ассетов (ключи `states` в GremlinSpriteManifest.json)

/// Явное разделение ролей спрайтов. Файлы перечисляются только в JSON — здесь только семантика для кода.
enum GremlinSpriteAssetRole: String, Sendable, CaseIterable {
    /// Циклы ожидания / присутствия (`idle` в манифесте).
    case idle
    /// Реакции, речь, комментарии (`talking` в манифесте).
    case talking
    /// Терминальная анимация один раз в конце сценария (`final` в манифесте). Не использовать как fallback для idle/talking.
    case final
}
