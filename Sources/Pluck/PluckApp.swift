import AppKit
import PluckKit
import SwiftUI

@main
struct PluckApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("Pluck", id: "main") {
            ContentView(model: appDelegate.model, actions: appDelegate.actions)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { PluckCommands(actions: appDelegate.actions) }

        Settings { SettingsView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PluckModel()
    private(set) lazy var actions = AppActions(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets the bare executable from `swift run` behave like the bundled app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Finder's "Open With" and files dropped on the Dock icon arrive here.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        actions.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
