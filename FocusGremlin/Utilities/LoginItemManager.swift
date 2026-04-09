import Foundation
import ServiceManagement

enum LoginItemManager {
    static func setStartAtLogin(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } else {
            throw NSError(domain: "FocusGremlin", code: 1, userInfo: [NSLocalizedDescriptionKey: "Требуется macOS 13+ для встроенного автозапуска."])
        }
    }
}
