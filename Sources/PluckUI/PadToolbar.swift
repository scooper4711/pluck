#if os(iOS)
import PluckKit
import SwiftUI

/// The iPad's toolbar: Open at the leading edge, the Images/Text switch in the middle, and the commands of the
/// mode on show at the trailing edge, with everything used less often in the More menu. A compact window, such as
/// the iPhone's, has no room for them at the top, so the mode's commands go in a bar along the bottom.
struct PluckToolbar: ToolbarContent {
    @Bindable var model: PluckModel
    let actions: AppActions
    @Binding var thumbnailSize: Double
    let isCompact: Bool

    private var hasSelection: Bool { !model.selectedImages.isEmpty }

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu("Open", systemImage: "folder") {
                Button("Open…", systemImage: "doc", action: actions.chooseDocuments)
                Button("Open from Scrollkeeper…", systemImage: "books.vertical",
                       action: actions.openFromScrollkeeper)
                OpenRecentMenu(recents: actions.recents) { actions.open([$0]) }
                Divider()
                Button("Close", systemImage: "xmark", action: actions.close)
                    .disabled(model.documentURL == nil)
            }
        }
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: $model.mode) {
                Text("Images").tag(PluckModel.Mode.images)
                Text("Text").tag(PluckModel.Mode.text)
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 180)
        }
        ToolbarItemGroup(placement: isCompact ? .bottomBar : .topBarTrailing) {
            modeTools
        }
        ToolbarItem(placement: .topBarTrailing) {
            moreMenu
        }
    }

    @ViewBuilder private var modeTools: some View {
        if model.mode == .images {
            imageTools
        } else {
            textTools
        }
    }

    @ViewBuilder private var imageTools: some View {
        Menu("Rotate and Flip", systemImage: "rotate.right") {
            EditButtons(actions: actions)
        }
        .disabled(!hasSelection)
        Button("Copy", systemImage: "doc.on.doc", action: actions.copySelection)
            .disabled(!hasSelection)
        Button("Quick Look", systemImage: "eye", action: actions.quickLook)
            .disabled(!hasSelection)
        Menu("Export", systemImage: "square.and.arrow.up") {
            Button("Export Selected…", action: actions.exportSelection)
                .disabled(!hasSelection)
            Button("Export All Shown…", action: actions.exportVisible)
                .disabled(model.visibleImages.isEmpty)
        }
    }

    @ViewBuilder private var textTools: some View {
        Menu("Format", systemImage: "textformat") {
            Picker("Format", selection: $model.textFormat) {
                ForEach(TextFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
        }
        Button("Copy All", systemImage: "doc.on.doc", action: actions.copyText)
            .disabled(model.visibleText.isEmpty)
        Button("Export", systemImage: "square.and.arrow.up", action: actions.exportText)
            .disabled(model.visibleText.isEmpty)
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            if model.mode == .images {
                Button("Select All", systemImage: "checkmark.circle", action: model.selectAllVisibleImages)
                    .disabled(model.visibleImages.isEmpty)
                Button("Deselect All", systemImage: "circle") { model.selectedImageIDs = [] }
                    .disabled(!hasSelection)
                Picker("Thumbnail Size", selection: $thumbnailSize) {
                    ForEach(ThumbnailSize.allCases) { size in
                        Text(size.title).tag(size.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Picker("Minimum Size", selection: $model.minimumDimension) {
                    Text("All sizes").tag(0)
                    ForEach([32, 64, 128, 256, 512], id: \.self) { size in
                        Text("≥ \(size) px").tag(size)
                    }
                }
                .pickerStyle(.menu)
                Divider()
            }
            Button("Settings…", systemImage: "gearshape") { actions.presenter.isShowingSettings = true }
            Button("About Pluck", systemImage: "info.circle") { actions.presenter.isShowingAbout = true }
            Link(destination: AppLinks.privacyPolicy) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        }
    }
}

/// The rotations and flips, for the toolbar's menu and an image's own.
struct EditButtons: View {
    let actions: AppActions

    var body: some View {
        Button("Rotate Left", systemImage: "rotate.left") { actions.apply(.rotateLeft) }
        Button("Rotate Right", systemImage: "rotate.right") { actions.apply(.rotateRight) }
        Button("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
            actions.apply(.flipHorizontal)
        }
        Button("Flip Vertical", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
            actions.apply(.flipVertical)
        }
    }
}
#endif
