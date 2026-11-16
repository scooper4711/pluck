#if os(macOS)
import SwiftUI
import TablesideShared

/// File ▸ Open from Scrollkeeper…: the browser in a window of its own.
struct ScrollkeeperWindow: View {
    static let id = "scrollkeeper"

    let bridge: ScrollkeeperBridge
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ScrollkeeperBrowser(bridge: bridge) { dismissWindow(id: Self.id) }
            .frame(width: 560, height: 480)
    }
}
#endif
