import AppKit
import PluckKit
import SwiftUI

@main
struct PluckApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // One window per PDF, as in Preview. Opening a PDF that already has a window brings it forward.
        WindowGroup(for: URL.self) { $url in
            DocumentWindow(url: url, router: appDelegate.router, recents: appDelegate.recents)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { PluckCommands(router: appDelegate.router, recents: appDelegate.recents) }

        Settings { SettingsView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let router = DocumentRouter()
    let recents = RecentDocuments(store: SystemRecentDocuments())

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets the bare executable from `swift run` behave like the bundled app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Finder's "Open With", the Dock's recent items and files dropped on the Dock icon arrive here.
    func application(_ application: NSApplication, open urls: [URL]) {
        router.open(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// The system's recent-documents list, which also feeds the Dock icon's menu.
struct SystemRecentDocuments: RecentDocumentStore {
    var urls: [URL] { NSDocumentController.shared.recentDocumentURLs }

    func note(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
}

/// A window and the one PDF it shows. `url` is the window's identity, which SwiftUI also uses
/// to restore the window on relaunch. A window without one is the empty window shown at launch.
struct DocumentWindow: View {
    let url: URL?
    let router: DocumentRouter
    let recents: RecentDocuments

    @State private var model = PluckModel()
    @State private var windowID = UUID()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let actions = AppActions(model: model, router: router)
        ContentView(model: model, actions: actions)
            .focusedSceneValue(\.documentActions, actions)
            .task(id: url) { await showDocument() }
            // File-open events go to `AppDelegate`. Accepting them here as well stops SwiftUI
            // opening an extra empty window for each one while a window already exists.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .onChange(of: router.pendingURLs, initial: true) { openPendingDocuments() }
            .task(id: router.hasDocumentWindows) { closeIfSuperseded() }
            .onChange(of: model.phase) { noteIfOpened() }
            .onDisappear { router.documentWindowDidClose(windowID) }
    }

    private func showDocument() async {
        guard let url else { return }
        router.documentWindowDidAppear(windowID)
        await model.open(url)
    }

    private func openPendingDocuments() {
        router.claimPending().forEach { openWindow(value: $0) }
    }

    /// The empty window only exists until a document is open. SwiftUI also creates one for each
    /// file-open event from Finder, and those close the same way. This runs as a task because a
    /// window cannot be dismissed while it is still appearing.
    private func closeIfSuperseded() {
        if url == nil, router.hasDocumentWindows { dismiss() }
    }

    private func noteIfOpened() {
        if model.phase == .ready, let url = model.documentURL { recents.note(url) }
    }
}

extension FocusedValues {
    /// The commands of the frontmost document window, for the menu bar.
    @Entry var documentActions: AppActions?
}
