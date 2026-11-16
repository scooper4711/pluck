#if os(macOS)
import PluckKit
import SwiftUI

/// A Mac document window: the page navigator beside the PDF's images or text.
struct ContentView: View {
    @Bindable var model: PluckModel
    let actions: AppActions

    @AppStorage("thumbnailSize") private var thumbnailSize = 180.0
    @State private var isDropTargeted = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            PageSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 150, ideal: 190, max: 900)
        } detail: {
            DocumentDetail(model: model, actions: actions, thumbnailSize: thumbnailSize,
                           isDropTargeted: isDropTargeted) { openWindow(id: ScrollkeeperWindow.id) }
        }
        .navigationTitle(model.documentURL?.lastPathComponent ?? "Pluck")
        .toolbar { PluckToolbar(model: model, actions: actions, thumbnailSize: $thumbnailSize) }
        .modifier(DocumentOpening(model: model, actions: actions, isDropTargeted: $isDropTargeted))
    }
}
#endif
