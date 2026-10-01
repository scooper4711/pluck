import AppKit
import Foundation

/// One image encoded for the pasteboard. PNG and TIFF are offered because, unlike WebP,
/// practically every app can paste them, and both keep the alpha channel.
public struct PasteboardImage: Sendable {
    let png: Data
    let tiff: Data

    public init(_ image: RasterImage) throws {
        png = try PNGEncoder.encode(image)
        tiff = try TIFFEncoder.encode(image)
    }

    var pasteboardItem: NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        return item
    }
}

public enum PasteboardWriter {
    /// Renders and encodes the images; slow, so run it off the main thread.
    public static func encode(_ requests: [RenderRequest]) throws -> [PasteboardImage] {
        try requests.map { try PasteboardImage($0.render()) }
    }

    /// Replaces the pasteboard's contents with one item per image.
    @MainActor
    public static func write(_ images: [PasteboardImage], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects(images.map(\.pasteboardItem))
    }
}
