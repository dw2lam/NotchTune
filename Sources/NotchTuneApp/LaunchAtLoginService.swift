import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` for registering/unregistering NotchTune as a
/// login item. `SMAppService.mainApp` is authoritative — the UI reads its
/// status on demand so the toggle stays in sync with System Settings ->
/// General -> Login Items changes that happen outside the app.
@MainActor
final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    /// `.enabled` and `.requiresApproval` both count as "on": if the user
    /// approved, we run at login; if they haven't approved yet, the OS will
    /// prompt them and our registration persists in the meantime.
    var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard !isEnabled else { return }
            try service.register()
        } else {
            let status = service.status
            guard status != .notRegistered, status != .notFound else { return }
            try service.unregister()
        }
    }
}
