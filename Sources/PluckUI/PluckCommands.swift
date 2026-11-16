#if os(macOS)
import PluckKit
import SwiftUI

/// The Mac's File and Help menu commands; the rest are `DocumentCommands`.
struct PluckCommands: Commands {
    let router: DocumentRouter
    @ObservedObject var recents: RecentDocuments
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { router.open(DocumentPanel.choosePDFs()) }
                .keyboardShortcut("o")
            Button("Open from Scrollkeeper…") { openWindow(id: ScrollkeeperWindow.id) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            OpenRecentMenu(recents: recents) { router.open([$0]) }
        }
        CommandGroup(replacing: .help) {
            Link("Pluck Privacy Policy", destination: AppLinks.privacyPolicy)
        }
    }
}
#endif
