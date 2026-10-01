import PluckKit
import SwiftUI

struct PluckToolbar: ToolbarContent {
    @Bindable var model: PluckModel
    let actions: AppActions
    @Binding var thumbnailSize: Double

    private var hasSelection: Bool { !model.selectedImages.isEmpty }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Open", systemImage: "folder", action: actions.chooseDocuments)
                .help("Open a PDF")
        }
        ToolbarItemGroup {
            editButton("Rotate Left", systemImage: "rotate.left", edit: .rotateLeft)
            editButton("Rotate Right", systemImage: "rotate.right", edit: .rotateRight)
            editButton("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                       edit: .flipHorizontal)
            editButton("Flip Vertical", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                       edit: .flipVertical)
        }
        ToolbarItemGroup {
            Button("Copy", systemImage: "doc.on.doc", action: actions.copySelection)
                .help("Copy the selected images")
                .disabled(!hasSelection)
            Menu("Export", systemImage: "square.and.arrow.up") {
                Button("Export Selected…", action: actions.exportSelection)
                    .disabled(!hasSelection)
                Button("Export All Shown…", action: actions.exportVisible)
                    .disabled(model.visibleImages.isEmpty)
            }
            .help("Export images as WebP")
        }
        ToolbarItemGroup {
            Picker("Minimum Size", selection: $model.minimumDimension) {
                Text("All sizes").tag(0)
                ForEach([32, 64, 128, 256, 512], id: \.self) { size in
                    Text("≥ \(size) px").tag(size)
                }
            }
            .help("Hide images smaller than this")
            Slider(value: $thumbnailSize, in: 96...360)
                .frame(width: 110)
                .help("Thumbnail size")
        }
    }

    private func editButton(_ title: String, systemImage: String, edit: ImageEdit) -> some View {
        Button(title, systemImage: systemImage) { actions.apply(edit) }
            .help(title)
            .disabled(!hasSelection)
    }
}
