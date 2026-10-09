import AppKit
import PluckKit
import UniformTypeIdentifiers

/// Supplies dragged images: a promised WebP file for Finder, and PNG data for apps that
/// accept pictures but not files.
final class ImageDragWriter: NSObject, NSFilePromiseProviderDelegate, NSPasteboardItemDataProvider {
    /// Where a file promise records the name it will use; it identifies an item on the pasteboard.
    private static let promisedFileName = NSPasteboard.PasteboardType(
        "com.apple.pasteboard.promised-suggested-file-name")

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()
    /// The images of the drag in progress, by promised file name. Only touched on the main thread.
    private var draggedImages: [String: DraggedImage] = [:]

    func provider(for item: ExportItem, exporter: ImageExporter) -> NSFilePromiseProvider {
        let dragged = DraggedImage(item: item, exporter: exporter)
        draggedImages[item.fileName] = dragged
        let provider = NSFilePromiseProvider(fileType: UTType.webP.identifier, delegate: self)
        provider.userInfo = dragged
        return provider
    }

    /// Adds PNG data to each promised file on the pasteboard, rendered only if a drop asks for it.
    /// Call once the drag's items are on the pasteboard. A file promise provider cannot offer the
    /// data itself: extra types added by subclassing it are advertised but never delivered.
    func offerImageData(on pasteboard: NSPasteboard) {
        for item in pasteboard.pasteboardItems ?? [] where draggedImage(for: item) != nil {
            item.setDataProvider(self, forTypes: [.png])
        }
    }

    // MARK: - NSPasteboardItemDataProvider

    func pasteboard(
        _: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard type == .png, let dragged = draggedImage(for: item),
              let png = try? PNGEncoder.encode(dragged.item.request.render()) else { return }
        item.setData(png, forType: .png)
    }

    func pasteboardFinishedWithDataProvider(_: NSPasteboard) {
        draggedImages = [:]
    }

    // MARK: - NSFilePromiseProviderDelegate

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType _: String) -> String {
        (provider.userInfo as? DraggedImage)?.item.fileName ?? "image.\(ImageExporter.fileExtension)"
    }

    func filePromiseProvider(
        _ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void
    ) {
        guard let dragged = provider.userInfo as? DraggedImage else {
            return completionHandler(PluckError.noDocument(operation: "write a dragged image"))
        }
        completionHandler(Result { try dragged.exporter.write(dragged.item, to: url) }.failure)
    }

    func operationQueue(for _: NSFilePromiseProvider) -> OperationQueue {
        queue
    }

    private func draggedImage(for item: NSPasteboardItem) -> DraggedImage? {
        item.string(forType: Self.promisedFileName).flatMap { draggedImages[$0] }
    }
}

private struct DraggedImage {
    let item: ExportItem
    let exporter: ImageExporter
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
