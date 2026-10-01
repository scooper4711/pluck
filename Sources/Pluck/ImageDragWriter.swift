import AppKit
import PluckKit
import UniformTypeIdentifiers

/// Supplies dragged images: a promised WebP file for Finder, and PNG data for apps that
/// accept pictures but not files.
final class ImageDragWriter: NSObject, NSFilePromiseProviderDelegate {
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    func provider(for item: ExportItem, exporter: ImageExporter) -> NSFilePromiseProvider {
        let provider = ImageDragProvider(fileType: UTType.webP.identifier, delegate: self)
        provider.userInfo = DraggedImage(item: item, exporter: exporter)
        return provider
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
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

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
        queue
    }
}

private struct DraggedImage {
    let item: ExportItem
    let exporter: ImageExporter
}

private final class ImageDragProvider: NSFilePromiseProvider {
    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.png]
    }

    override func writingOptions(
        forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        type == .png ? .promised : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    /// Only called if the drop target asks for PNG, so the full-size render happens on demand.
    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard type == .png else { return super.pasteboardPropertyList(forType: type) }
        guard let dragged = userInfo as? DraggedImage else { return nil }
        return try? PNGEncoder.encode(dragged.item.request.render())
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
