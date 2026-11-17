#if os(iOS)
import PluckKit
import SwiftUI

/// An iPad window: the page navigator beside the PDF's images or text. In portrait the navigator slides over
/// them from the leading edge; on the iPhone, and in a narrow window, each is a screen of its own.
struct PadContentView: View {
    @Bindable var model: PluckModel
    let actions: AppActions
    @Bindable var presenter: PadPresenter

    @AppStorage("thumbnailSize") private var thumbnailSize = ThumbnailSize.medium.rawValue
    @State private var isDropTargeted = false
    /// Read here, outside the split view, whose columns are compact on the iPad too.
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationSplitView(columnVisibility: $presenter.columnVisibility,
                            preferredCompactColumn: $presenter.compactColumn) {
            PageSidebar(model: model)
                .navigationTitle(documentName ?? "Pages")
                .navigationBarTitleDisplayMode(.inline)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
                .toolbar { compactSidebarTools }
        } detail: {
            DocumentDetail(model: model, actions: actions, thumbnailSize: thumbnailSize,
                           isDropTargeted: isDropTargeted, openFromScrollkeeper: actions.openFromScrollkeeper)
                .navigationTitle(documentName ?? "Pluck")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    PluckToolbar(model: model, actions: actions, thumbnailSize: $thumbnailSize,
                                 isCompact: isCompact)
                }
        }
        .modifier(DocumentOpening(model: model, actions: actions, isDropTargeted: $isDropTargeted))
    }

    private var isCompact: Bool {
        sizeClass == .compact
    }

    /// On its own screen the navigator has a way back to the images or text of the pages chosen.
    @ToolbarContentBuilder private var compactSidebarTools: some ToolbarContent {
        if isCompact {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { presenter.compactColumn = .detail }
            }
        }
    }

    private var documentName: String? {
        model.documentURL?.deletingPathExtension().lastPathComponent
    }
}

/// The grid's thumbnail sizes, in points. The Mac has a slider; a menu suits a touch toolbar better.
enum ThumbnailSize: Double, CaseIterable, Identifiable {
    case small = 120
    case medium = 180
    case large = 260

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}
#endif
