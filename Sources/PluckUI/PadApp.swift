#if os(iOS)
import AppNotices
import PluckKit
import QuickLook
import SwiftUI
import TablesideShared
import UIKit

/// The iPad app: each window shows one PDF, and opening another replaces it. `ios/App` starts it.
public struct PluckApp: App {
    @StateObject private var recents = RecentDocuments(store: BookmarkedRecentDocuments())

    public init() {
        ImageDrag.removeLeftovers()
    }

    public var body: some Scene {
        WindowGroup {
            PadRootView(recents: recents)
        }
        .commands {
            PadCommands(recents: recents)
            DocumentCommands()
            AboutCommands(info: .pluck)
        }

        AboutWindow(info: .pluck)
    }
}

/// The File and Help commands for a hardware keyboard and the iPad's menu bar; the rest are `DocumentCommands`.
struct PadCommands: Commands {
    let recents: RecentDocuments
    @FocusedValue(\.documentActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open…") { actions?.chooseDocuments() }
                .keyboardShortcut("o")
                .disabled(actions == nil)
            Button("Open from Scrollkeeper…") { actions?.openFromScrollkeeper() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(actions == nil)
            OpenRecentMenu(recents: recents) { actions?.open([$0]) }
                .disabled(actions == nil)
            Divider()
            Button("Close") { actions?.close() }
                .disabled(actions?.model.documentURL == nil)
        }
        CommandGroup(replacing: .help) {
            Link("Pluck Privacy Policy", destination: AppLinks.privacyPolicy)
        }
    }
}

/// A window with what it presents: the file browser, Quick Look, and the Open from Scrollkeeper, Settings and
/// About sheets.
struct PadRootView: View {
    let recents: RecentDocuments
    @State private var model = PluckModel()
    @State private var presenter = PadPresenter()
    @State private var scrollkeeper = ScrollkeeperBridge(configuration: .pluck, launcher: PadLauncher(),
                                                         libraryFolder: ToolkitGroup.scrollkeeperFolder())
    @State private var libraryChanges: LibraryChangeObserver?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let actions = AppActions(model: model, presenter: presenter, recents: recents)
        PadContentView(model: model, actions: actions, presenter: presenter)
            .focusedSceneValue(\.documentActions, actions)
            .fileImporter(isPresented: $presenter.isChoosingFile,
                          allowedContentTypes: presenter.fileRequest.contentTypes,
                          onCompletion: actions.finishChoosing)
            .fileMover(isPresented: $presenter.isSavingTextFile, file: presenter.textFile,
                       onCompletion: actions.finishSavingText)
            .quickLookPreview($presenter.previewFile, in: presenter.previewFiles)
            .sheet(isPresented: $presenter.isShowingScrollkeeper) { scrollkeeperSheet }
            .sheet(isPresented: $presenter.isShowingSettings) { settingsSheet }
            .sheet(isPresented: $presenter.isShowingAbout) { AboutSheet(info: .pluck) }
            .alert(presenter.errorMessage ?? "", isPresented: isShowingError) {
                Button("OK", role: .cancel) { presenter.errorMessage = nil }
            }
            .onOpenURL { actions.open([$0]) }
            .onChange(of: scenePhase) { if scenePhase == .active { scrollkeeper.refreshLibrary() } }
            .onChange(of: model.phase) { noteIfOpened() }
            .onAppear { startFollowingScrollkeeper(opening: actions) }
            #if DEBUG
            .task { if let sample = UITestSample.urlIfRequested() { actions.open([sample]) } }
            #endif
    }

    private var isShowingError: Binding<Bool> {
        Binding { presenter.errorMessage != nil } set: { if !$0 { presenter.errorMessage = nil } }
    }

    private var scrollkeeperSheet: some View {
        NavigationStack {
            ScrollkeeperBrowser(bridge: scrollkeeper) { presenter.isShowingScrollkeeper = false }
                .navigationTitle("Open from Scrollkeeper")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { presenter.isShowingSettings = false }
                    }
                }
        }
    }

    /// A PDF that opened joins Open Recent, bookmarked while the app may still read it.
    private func noteIfOpened() {
        if model.phase == .ready, let url = model.documentURL { recents.note(url) }
    }

    /// Scrollkeeper says when it rewrites its library list, so an open list follows its downloads.
    private func startFollowingScrollkeeper(opening actions: AppActions) {
        scrollkeeper.openDocuments = { urls in actions.open(urls) }
        guard libraryChanges == nil else { return }
        libraryChanges = LibraryChangeObserver { [scrollkeeper] in scrollkeeper.refreshLibrary() }
    }
}

/// The system side of `ApplicationLauncher` on the iPad. Scrollkeeper there takes no requests in the background:
/// Pluck reads its shared library and brings it forward to download a title.
struct PadLauncher: ApplicationLauncher {
    // A literal URL that is known to parse.
    // swiftlint:disable:next force_unwrapping
    private static let scrollkeeperURL = URL(string: "scrollkeeper://")!

    var takesRequests: Bool { false }

    /// Scrollkeeper's link, when it registers one, or else its folder in the App Group, which it makes on its
    /// first launch.
    func isInstalled(_ bundleIdentifier: String) -> Bool {
        if UIApplication.shared.canOpenURL(Self.scrollkeeperURL) { return true }
        guard let folder = ToolkitGroup.scrollkeeperFolder() else { return false }
        return FileManager.default.fileExists(atPath: folder.path)
    }

    func openInBackground(_ url: URL) {
        // Nothing is ever asked of Scrollkeeper on the iPad (`takesRequests`).
    }

    func launch(_ bundleIdentifier: String) {
        UIApplication.shared.open(Self.scrollkeeperURL)
    }
}
#endif
