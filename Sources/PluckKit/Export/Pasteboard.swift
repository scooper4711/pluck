import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One value on a pasteboard item: data, or text the pasteboard stores in its own encoding.
public enum PasteboardValue: Equatable, Sendable {
    case data(Data)
    case text(String)
}

/// One pasteboard item: the same content in several forms, by type identifier. An app pasting takes the richest
/// form it understands.
public typealias PasteboardItem = [String: PasteboardValue]

/// Where copies go. The system pasteboard conforms; tests use one in memory, because the system's exists only in a
/// desktop session, which CI runners don't have.
@MainActor
public protocol Pasteboard: AnyObject {
    /// Replaces the pasteboard's contents with these items.
    func replaceContents(with items: [PasteboardItem])
}

#if os(macOS)
extension NSPasteboard: Pasteboard {
    public func replaceContents(with items: [PasteboardItem]) {
        clearContents()
        writeObjects(items.map(Self.pasteboardItem))
    }

    private static func pasteboardItem(_ item: PasteboardItem) -> NSPasteboardItem {
        let pasteboardItem = NSPasteboardItem()
        for (typeIdentifier, value) in item {
            let type = NSPasteboard.PasteboardType(typeIdentifier)
            switch value {
            case .data(let data): pasteboardItem.setData(data, forType: type)
            case .text(let text): pasteboardItem.setString(text, forType: type)
            }
        }
        return pasteboardItem
    }
}
#else
extension UIPasteboard: Pasteboard {
    public func replaceContents(with items: [PasteboardItem]) {
        self.items = items.map { item in
            item.mapValues { value -> Any in
                switch value {
                case .data(let data): data
                case .text(let text): text
                }
            }
        }
    }
}
#endif
