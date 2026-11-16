import PluckKit
import SwiftUI

/// Open Recent: the PDFs opened lately, newest first, and Clear Menu. In the Mac's File menu, and on the iPad in
/// the menu bar's File menu and the toolbar's Open menu.
struct OpenRecentMenu: View {
    @ObservedObject var recents: RecentDocuments
    let open: (URL) -> Void

    var body: some View {
        Menu("Open Recent") {
            ForEach(recents.urls, id: \.self) { url in
                Button(url.lastPathComponent) { open(url) }
            }
            Divider()
            Button("Clear Menu", action: recents.clear)
                .disabled(recents.urls.isEmpty)
        }
    }
}
