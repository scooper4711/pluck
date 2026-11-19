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

    /// The image as one pasteboard item, in both forms.
    var pasteboardItem: PasteboardItem {
        [UTType.png.identifier: .data(png), UTType.tiff.identifier: .data(tiff)]
    }
}

public enum PasteboardWriter {
    /// Renders and encodes the images; slow, so run it off the main thread.
    public static func encode(_ requests: [RenderRequest]) throws -> [PasteboardImage] {
        try requests.map { try PasteboardImage($0.render()) }
    }

    /// Replaces the pasteboard's contents with one item per image.
    @MainActor
    public static func write(_ images: [PasteboardImage], to pasteboard: any Pasteboard) {
        pasteboard.replaceContents(with: images.map(\.pasteboardItem))
    }

    /// Replaces the pasteboard's contents with a plain string.
    @MainActor
    public static func write(_ text: String, to pasteboard: any Pasteboard) {
        pasteboard.replaceContents(with: [[UTType.utf8PlainText.identifier: .text(text)]])
    }
}
