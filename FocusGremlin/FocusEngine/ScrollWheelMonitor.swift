import AppKit

/// Глобальный монитор скролла требует «Мониторинг ввода» / Accessibility в зависимости от версии ОС.
/// Если монитор недоступен, `ScrollSessionTracker` просто не получает событий.
final class ScrollWheelMonitor {
    private var monitor: Any?
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [handler] _ in
            handler()
        }
        if monitor == nil {
            AppLogger.focus.debug("Глобальный монитор скролла недоступен — проверьте Accessibility / Input Monitoring.")
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        stop()
    }
}
