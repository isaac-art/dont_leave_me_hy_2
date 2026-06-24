import Foundation
import ServiceManagement

/// Registers/unregisters the app as a macOS login item using the modern
/// `SMAppService` API (macOS 13+). No helper bundle required for the main app.
enum LoginItemManager {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. `register()` may surface a "Login Items" approval
    /// in System Settings the first time.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("LoginItemManager: %@", error.localizedDescription)
            return false
        }
    }
}
