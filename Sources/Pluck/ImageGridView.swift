import AppKit
import PluckKit
import SwiftUI

/// What the grid should currently display.
struct ImageGridContent {
    var images: [ExtractedImage] = []
    var transforms: [String: ImageTransform] = [:]
    var selection: Set<String> = []
    var thumbnailSize: CGFloat = 180
}

/// The main view: a grid of extracted images. Built on `NSCollectionView` for its rubber-band
/// selection and multi-item drag, neither of which a SwiftUI grid offers.
struct ImageGridView: NSViewRepresentable {
    let images: [ExtractedImage]
    let transforms: [String: ImageTransform]
    @Binding var selection: Set<String>
    let thumbnailSize: CGFloat
    let actions: AppActions

    func makeCoordinator() -> ImageGridCoordinator {
        ImageGridCoordinator(actions: actions)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let collectionView = ImageCollectionView()
        context.coordinator.attach(to: collectionView)
        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSelectionChange = { selection = $0 }
        context.coordinator.show(ImageGridContent(
            images: images, transforms: transforms, selection: selection, thumbnailSize: thumbnailSize))
    }
}

@MainActor
final class ImageGridCoordinator: NSObject, NSCollectionViewDelegate {
    var onSelectionChange: (Set<String>) -> Void = { _ in }

    private let actions: AppActions
    private let layout = NSCollectionViewFlowLayout()
    private var content = ImageGridContent()
    private var imagesByID: [String: ExtractedImage] = [:]
    private var dataSource: NSCollectionViewDiffableDataSource<Int, String>?
    private weak var collectionView: ImageCollectionView?
    private let dragWriter = ImageDragWriter()
    private let contextMenu: ImageGridMenu

    init(actions: AppActions) {
        self.actions = actions
        contextMenu = ImageGridMenu(actions: actions)
    }

    func attach(to collectionView: ImageCollectionView) {
        self.collectionView = collectionView
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(ImageGridItem.self, forItemWithIdentifier: ImageGridItem.identifier)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.delegate = self
        collectionView.onCopy = actions.copySelection
        collectionView.menu = contextMenu.menu
        dataSource = NSCollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] view, path, id in
            let item = view.makeItem(withIdentifier: ImageGridItem.identifier, for: path)
            self?.configure(item, imageID: id)
            return item
        }
    }

    func show(_ newContent: ImageGridContent) {
        content = newContent
        imagesByID = Dictionary(uniqueKeysWithValues: newContent.images.map { ($0.id, $0) })
        layout.itemSize = ImageGridItem.size(forThumbnailSize: newContent.thumbnailSize)
        applySnapshot()
        refreshVisibleItems()
        synchronizeSelection()
    }

    // MARK: - NSCollectionViewDelegate

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        reportSelection()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        reportSelection()
    }

    func collectionView(
        _ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard let id = dataSource?.itemIdentifier(for: indexPath),
              let item = actions.model.exportItem(forImageID: id) else { return nil }
        return dragWriter.provider(for: item, exporter: actions.model.exporter)
    }

    func collectionView(
        _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>
    ) {
        dragWriter.offerImageData(on: session.draggingPasteboard)
    }

    // MARK: - Private

    private func applySnapshot() {
        let ids = content.images.map(\.id)
        guard let dataSource, dataSource.snapshot().itemIdentifiers != ids else { return }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func refreshVisibleItems() {
        guard let collectionView, let dataSource else { return }
        for item in collectionView.visibleItems() {
            guard let path = collectionView.indexPath(for: item),
                  let id = dataSource.itemIdentifier(for: path) else { continue }
            configure(item, imageID: id)
        }
    }

    private func configure(_ item: NSCollectionViewItem, imageID: String) {
        guard let item = item as? ImageGridItem, let image = imagesByID[imageID] else { return }
        item.show(image, transform: content.transforms[imageID] ?? .identity)
    }

    private func synchronizeSelection() {
        guard let collectionView, let dataSource else { return }
        let wanted = Set(content.selection.compactMap { dataSource.indexPath(for: $0) })
        if collectionView.selectionIndexPaths != wanted {
            collectionView.selectionIndexPaths = wanted
        }
    }

    private func reportSelection() {
        guard let collectionView, let dataSource else { return }
        onSelectionChange(Set(collectionView.selectionIndexPaths.compactMap { dataSource.itemIdentifier(for: $0) }))
    }
}

/// The grid's context menu.
@MainActor
final class ImageGridMenu: NSObject {
    private static let edits: [(title: String, edit: ImageEdit)] = [
        ("Rotate Left", .rotateLeft), ("Rotate Right", .rotateRight),
        ("Flip Horizontal", .flipHorizontal), ("Flip Vertical", .flipVertical)
    ]

    let menu = NSMenu()
    private let actions: AppActions

    init(actions: AppActions) {
        self.actions = actions
        super.init()
        addItem("Copy", action: #selector(copySelection))
        addItem("Export…", action: #selector(exportSelection))
        menu.addItem(.separator())
        for (index, entry) in Self.edits.enumerated() {
            addItem(entry.title, action: #selector(applyEdit(_:))).tag = index
        }
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func copySelection() { actions.copySelection() }

    @objc private func exportSelection() { actions.exportSelection() }

    @objc private func applyEdit(_ sender: NSMenuItem) { actions.apply(Self.edits[sender.tag].edit) }
}
