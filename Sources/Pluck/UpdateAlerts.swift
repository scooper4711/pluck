import AppKit
import PluckKit
import SwiftUI

extension AppUpdater {
    /// The updater for Pluck's releases on GitHub.
    static let shared = AppUpdater.live(product: UpdateProduct(name: "Pluck", repository: "scooper4711/pluck"))
}

/// Tells the user what an update check found and asks before downloading anything. The alerts belong to the
/// app rather than a window, so they appear once however many PDFs are open.
@MainActor
enum UpdateAlerts {
    /// The check when the app opens, unless the user turned it off; it speaks up only about a newer version.
    static func checkAtLaunch(_ updater: AppUpdater) async {
        guard updater.checksAtLaunch(in: .standard) else { return }
        await updater.checkForUpdateQuietly()
        await present(updater)
    }

    /// The check the user asked for, which always reports its result.
    static func check(_ updater: AppUpdater) async {
        await updater.checkForUpdate()
        await present(updater)
    }

    private static func present(_ updater: AppUpdater) async {
        switch updater.state {
        case .available: await offerDownload(updater)
        case let .downloaded(_, file): offerDiskImage(file, updater: updater)
        case .upToDate, .failed:
            _ = alert(for: updater, buttons: ["OK"]).runModal()
            updater.dismiss()
        case .idle, .checking, .downloading: break
        }
    }

    private static func offerDownload(_ updater: AppUpdater) async {
        guard alert(for: updater, buttons: ["Download", "Not Now"]).runModal() == .alertFirstButtonReturn else {
            updater.dismiss()
            return
        }
        await updater.downloadUpdate()
        await present(updater)
    }

    private static func offerDiskImage(_ file: URL, updater: AppUpdater) {
        let choice = alert(for: updater, buttons: ["Open Disk Image", "Show in Finder", "Later"]).runModal()
        switch choice {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(file)
        case .alertSecondButtonReturn: NSWorkspace.shared.activateFileViewerSelecting([file])
        default: break
        }
        updater.dismiss()
    }

    private static func alert(for updater: AppUpdater, buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = updater.title
        alert.informativeText = updater.message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert
    }
}

/// Check for Updates… in the app menu, below About.
struct UpdateCommands: Commands {
    let updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(updater.state.isBusy ? updater.title : "Check for Updates…") {
                Task { await UpdateAlerts.check(updater) }
            }
            .disabled(updater.state.isBusy)
        }
    }
}
