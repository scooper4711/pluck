#if os(iOS)
import PluckKit
import SwiftUI
import UniformTypeIdentifiers

/// The iPad's image grid. A tap selects an image or deselects it, touching and holding opens its menu, and
/// an image can be dragged into another app.
struct ImageGrid: View {
    @Bindable var model: PluckModel
    let actions: AppActions
    let thumbnailSize: Double

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 4)], spacing: 4) {
                ForEach(model.visibleImages) { image in
                    ImageCell(image: image, transform: model.transform(for: image), thumbnailSize: thumbnailSize,
                              isSelected: model.selectedImageIDs.contains(image.id))
                        .onTapGesture { model.toggleSelection(ofImage: image.id) }
                        .contextMenu { menu(for: image) }
                        .onDrag { dragProvider(for: image) }
                }
            }
            .padding(12)
        }
        .background {
            SelectAllResponder(selection: model.selectedImageIDs, selectAll: model.selectAllVisibleImages)
        }
    }

    private var cellWidth: CGFloat { thumbnailSize + ImageCell.padding * 2 }

    /// The menu acts on the selection; on an image that isn't selected, that image becomes the selection.
    @ViewBuilder
    private func menu(for image: ExtractedImage) -> some View {
        let actions = MenuActions(actions: actions, imageID: image.id)
        Button("Copy", systemImage: "doc.on.doc") { actions.run { $0.copySelection() } }
        Button("Quick Look", systemImage: "eye") { actions.run { $0.quickLook() } }
        Button("Export…", systemImage: "square.and.arrow.up") { actions.run { $0.exportSelection() } }
        Divider()
        Button("Show Page in Sidebar", systemImage: "sidebar.left") {
            actions.run { $0.revealPageOfSelectedImage() }
        }
        Divider()
        Button("Rotate Left", systemImage: "rotate.left") { actions.run { $0.apply(.rotateLeft) } }
        Button("Rotate Right", systemImage: "rotate.right") { actions.run { $0.apply(.rotateRight) } }
        Button("Flip Horizontal") { actions.run { $0.apply(.flipHorizontal) } }
        Button("Flip Vertical") { actions.run { $0.apply(.flipVertical) } }
    }

    private func dragProvider(for image: ExtractedImage) -> NSItemProvider {
        guard let item = model.exportItem(forImageID: image.id) else { return NSItemProvider() }
        return ImageDrag.provider(for: item, exporter: model.exporter)
    }
}

/// Answers the system's Select All (⌘A, and Edit ▸ Select All in the menu bar) for the grid. The system sends it
/// to whatever has the keyboard, so the grid takes the keyboard when it appears, and again when the selection
/// changes, since a search field in a sheet may have had it in between.
private struct SelectAllResponder: UIViewRepresentable {
    /// Read so that a change of selection updates the view.
    let selection: Set<String>
    let selectAll: () -> Void

    func makeUIView(context _: Context) -> ResponderView {
        ResponderView()
    }

    func updateUIView(_ view: ResponderView, context _: Context) {
        view.onSelectAll = selectAll
        if view.window != nil, !view.isFirstResponder { view.becomeFirstResponder() }
    }

    final class ResponderView: UIView {
        var onSelectAll: () -> Void = {
            // Nothing to select until the grid connects it to the model.
        }

        override var canBecomeFirstResponder: Bool { true }

        /// ⌘A with a hardware keyboard, ahead of the system's own, which would look for text to select.
        override var keyCommands: [UIKeyCommand]? {
            let command = UIKeyCommand(input: "a", modifierFlags: .command, action: #selector(selectAll(_:)))
            command.wantsPriorityOverSystemBehavior = true
            return [command]
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
        }

        override func selectAll(_: Any?) {
            onSelectAll()
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            action == #selector(selectAll(_:)) || super.canPerformAction(action, withSender: sender)
        }
    }
}

/// Runs a command for an image's menu, after making the image the selection when it isn't part of it.
@MainActor
private struct MenuActions {
    let actions: AppActions
    let imageID: String

    func run(_ command: (AppActions) -> Void) {
        actions.model.selectForMenu(imageID: imageID)
        command(actions)
    }
}

/// One cell: the image over a checkerboard, so transparency is visible, with its pixel size beneath.
private struct ImageCell: View {
    static let padding: CGFloat = 8

    let image: ExtractedImage
    let transform: ImageTransform
    let thumbnailSize: Double
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            thumbnail
                .frame(width: thumbnailSize, height: thumbnailSize)
            Text(image.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(Self.padding)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18))
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image, \(image.caption)")
        .accessibilityIdentifier("image")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The image shrunk to fit, but never enlarged past its own pixels.
    private var thumbnail: some View {
        let shown = (try? transform.apply(to: image.thumbnail)) ?? image.thumbnail
        let scale = min(thumbnailSize / Double(shown.width), thumbnailSize / Double(shown.height), 1)
        return Image(decorative: shown, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: Double(shown.width) * scale, height: Double(shown.height) * scale)
            .background { Checkerboard() }
            .border(Color(.separator), width: 0.5)
    }
}

private struct Checkerboard: View {
    private static let checkSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.97)))
            let dark = GraphicsContext.Shading.color(Color(white: 0.82))
            for row in 0..<Int(ceil(size.height / Self.checkSize)) {
                for column in stride(from: row % 2, to: Int(ceil(size.width / Self.checkSize)), by: 2) {
                    context.fill(Path(CGRect(
                        x: CGFloat(column) * Self.checkSize, y: CGFloat(row) * Self.checkSize,
                        width: Self.checkSize, height: Self.checkSize)), with: dark)
                }
            }
        }
        .clipped()
    }
}

/// Supplies a dragged image: a WebP file, which Files keeps, and PNG data for apps that take pictures. Each is
/// made only when a drop asks for it.
enum ImageDrag {
    /// Where dragged files are written before the system copies them to where they were dropped.
    private static var folder: URL { FileManager.default.temporaryDirectory.appending(path: "Drags") }

    static func provider(for item: ExportItem, exporter: ImageExporter) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = item.baseName
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.webP.identifier, fileOptions: [], visibility: .all
        ) { completion in
            let result = Result { try write(item, with: exporter) }
            completion(try? result.get(), false, result.failure)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            let result = Result { try PNGEncoder.encode(item.request.render()) }
            completion(try? result.get(), result.failure)
            return nil
        }
        return provider
    }

    /// Deletes the files of earlier drags, which the system has long since copied.
    static func removeLeftovers() {
        try? FileManager.default.removeItem(at: folder)
    }

    private static func write(_ item: ExportItem, with exporter: ImageExporter) throws -> URL {
        let directory = folder.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: item.fileName)
        try exporter.write(item, to: file)
        return file
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
#endif
