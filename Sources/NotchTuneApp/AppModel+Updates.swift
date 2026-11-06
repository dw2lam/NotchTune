import AppKit
import Foundation

/// What the updater needs from the rest of the app before it restarts it.
extension AppModel {
    func connectUpdateChecker() {
        updateChecker.restartContext = { [weak self] in
            guard let self else { return UpdateRestartContext() }
            return UpdateRestartContext(agentsWaiting: liveAttentionCount, mirrorOpen: mirror.isRunning)
        }
        updateChecker.confirmRestartWithAgentsWaiting = { [weak self] in
            self?.confirmRestartWithAgentsWaiting() ?? true
        }
    }

    /// The app menu's item. Scheduled-style checks are silent, so Settings
    /// comes forward to show the answer; it also holds "Restart to Update"
    /// when an update is already prepared.
    func checkForUpdatesFromMenu() {
        showSettings()
        NotificationCenter.default.post(name: .notchTuneSelectSettingsTab, object: SettingsTab.general.rawValue)
        updateChecker.checkForUpdates()
    }

    private func confirmRestartWithAgentsWaiting() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = lang.t("update.restart.confirm.title")
        alert.informativeText = lang.t("update.restart.confirm.message")
        alert.addButton(withTitle: lang.t("update.restart.confirm.cancel"))
        alert.addButton(withTitle: lang.t("update.restart.confirm.action"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
