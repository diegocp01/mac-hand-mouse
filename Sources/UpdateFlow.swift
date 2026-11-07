import AppKit

/// Menu-driven check for a newer commit on GitHub and the hand-off to the relaunch helper.
final class UpdateFlow {
    private let menuItem: NSMenuItem
    private var checking = false
    /// Runs right before the helper replaces the app, so the camera is off first.
    var prepareForUpdate: (() -> Void)?

    init(menuItem: NSMenuItem) { self.menuItem = menuItem }

    func checkForUpdates() {
        guard !checking else { return }
        guard let checkout = SourceUpdate.checkoutURL() else {
            alert(title: "Updates aren’t configured",
                  detail: "Install Hand Mouse from its GitHub source checkout once. The installer will connect this menu to that checkout.")
            return
        }
        checking = true
        menuItem.isEnabled = false
        menuItem.title = "Checking for Updates…"
        let installedCommit = Bundle.main.object(forInfoDictionaryKey: "HandMouseSourceCommit") as? String
        let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try SourceUpdate.check(checkout: checkout,
                installedCommit: installedCommit, installedVersion: installedVersion) }
            DispatchQueue.main.async { self?.finish(result, checkout: checkout) }
        }
    }

    /// Reports the outcome of an update the helper finished before this launch.
    func showCompletedUpdate() {
        guard let result = SourceUpdate.takeResult() else { return }
        alert(title: result.success ? "Hand Mouse updated" : "Update didn’t finish", detail: result.detail)
    }

    private func finish(_ result: Result<UpdateCheck, Error>, checkout: URL) {
        checking = false
        menuItem.isEnabled = true
        menuItem.title = "Check for Updates…"
        switch result {
        case .failure(let error):
            alert(title: "Couldn’t check for updates", detail: error.localizedDescription)
        case .success(let check):
            switch check.comparison {
            case .current:
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "current"
                alert(title: "Hand Mouse is up to date", detail: "Version \(version) matches the latest version on GitHub.")
            case .available:
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "A Hand Mouse update is available"
                alert.informativeText = "Install version \(check.remoteVersion ?? "the latest version") from GitHub? Hand Mouse will pause, update, and reopen."
                alert.addButton(withTitle: "Update and Restart")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                beginUpdate(checkout: checkout, expectedCommit: check.remoteCommit)
            }
        }
    }

    private func beginUpdate(checkout: URL, expectedCommit: String) {
        guard let helper = Bundle.main.url(forResource: "update-and-relaunch", withExtension: "sh"),
              let stateDirectory = SourceUpdate.stateDirectory() else {
            alert(title: "Update helper unavailable", detail: "Reinstall Hand Mouse from the source checkout to repair the updater.")
            return
        }
        prepareForUpdate?()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [helper.path, checkout.path, Bundle.main.bundleURL.path,
                             String(ProcessInfo.processInfo.processIdentifier), expectedCommit, stateDirectory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            alert(title: "Update couldn’t start", detail: error.localizedDescription)
        }
    }

    private func alert(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
