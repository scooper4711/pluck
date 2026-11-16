import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit

/// The system pasteboard: `NSPasteboard` on the Mac, `UIPasteboard` on the iPad.
public typealias SystemPasteboard = NSPasteboard
#else
import UIKit

/// The system pasteboard: `NSPasteboard` on the Mac, `UIPasteboard` on the iPad.
public typealias SystemPasteboard = UIPasteboard
#endif

/// One image encoded for the pasteboard. PNG and TIFF are offered because, unlike WebP,
/// practically every app can paste them, and both keep the alpha channel.
public struct PasteboardImage: Sendable {
    let png: Data
    let tiff: Data

    public init(_ image: RasterImage) throws {
        png = try PNGEncoder.encode(image)
        tiff = try TIFFEncoder.encode(image)
    }

    #if os(macOS)
    var pasteboardItem: NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        return item
    }
    #else
    /// The image as one pasteboard item, by type identifier.
    var pasteboardItem: [String: Any] {
        [UTType.png.identifier: png, UTType.tiff.identifier: tiff]
    }
    #endif
}

public enum PasteboardWriter {
    /// Renders and encodes the images; slow, so run it off the main thread.
    public static func encode(_ requests: [RenderRequest]) throws -> [PasteboardImage] {
        try requests.map { try PasteboardImage($0.render()) }
    }

    /// Replaces the pasteboard's contents with one item per image.
    @MainActor
    public static func write(_ images: [PasteboardImage], to pasteboard: SystemPasteboard) {
        #if os(macOS)
        pasteboard.clearContents()
        pasteboard.writeObjects(images.map(\.pasteboardItem))
        #else
        pasteboard.items = images.map(\.pasteboardItem)
        #endif
    }

    /// Replaces the pasteboard's contents with a plain string.
    @MainActor
    public static func write(_ text: String, to pasteboard: SystemPasteboard) {
        #if os(macOS)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        pasteboard.string = text
        #endif
    }
}
