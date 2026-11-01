import Foundation
import ServiceManagement

/// "Launch at login" through the system's main-app login item service.
enum LoginItem {
    /// A bundle inside a build product points at a throwaway path, which must never be registered.
    private static let ephemeralPathMarkers = ["/DerivedData/", "/.build/", "/Build/Products/"]

    /// False while Sandia runs from Xcode or a local build, where registering would point at a temporary app.
    static var isSupportedLocation: Bool {
        let path = Bundle.main.bundlePath
        return !ephemeralPathMarkers.contains { path.contains($0) }
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Registers or unregisters the login item and returns the state macOS actually reports afterwards.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupportedLocation else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Sandia: login item update failed: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
