import OSLog

enum AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "FocusGremlin"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let focus = Logger(subsystem: subsystem, category: "focus")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let llm = Logger(subsystem: subsystem, category: "llm")
}
