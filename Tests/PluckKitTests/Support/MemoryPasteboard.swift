import CoreGraphics
import Foundation
@testable import PluckKit

/// A pasteboard in memory: the system's exists only in a desktop session, which CI runners don't have.
@MainActor
final class MemoryPasteboard: Pasteboard {
    private(set) var items: [PasteboardItem] = []

    func replaceContents(with items: [PasteboardItem]) {
        self.items = items
    }

    /// The data form of an item, or nil when it has none of that type.
    func data(_ typeIdentifier: String, item index: Int = 0) -> Data? {
        guard items.indices.contains(index), case .data(let data) = items[index][typeIdentifier] else { return nil }
        return data
    }

    /// The text form of an item, or nil when it has none of that type.
    func text(_ typeIdentifier: String, item index: Int = 0) -> String? {
        guard items.indices.contains(index), case .text(let text) = items[index][typeIdentifier] else { return nil }
        return text
    }
}

enum DesktopSession {
    /// Whether this process runs in a desktop session, where the system pasteboard exists.
    static var isAvailable: Bool { CGSessionCopyCurrentDictionary() != nil }
}
