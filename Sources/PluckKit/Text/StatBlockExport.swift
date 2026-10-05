import AppKit
import UniformTypeIdentifiers

/// Stat blocks on the pasteboard and in drags, for apps such as Combat Pad that turn them into creatures.
///
/// The data is JSON, `{ "format": 1, "blocks": [StatBlock] }`, under the type
/// `io.github.scooper4711.pluck.statblock`. Each block keeps its name, level, traits, entries (bold label
/// plus styled runs, with action glyphs as tokens such as `[two-actions]`), subtier and source. Plain text is
/// written alongside for every other app.
public enum StatBlockExport {
    public static let typeIdentifier = "io.github.scooper4711.pluck.statblock"
    public static let currentFormat = 1

    public static var contentType: UTType { UTType(exportedAs: typeIdentifier, conformingTo: .json) }

    private struct Payload: Codable {
        var format: Int
        var blocks: [StatBlock]
    }

    public static func data(for blocks: [StatBlock]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Payload(format: currentFormat, blocks: blocks))
    }

    public static func blocks(from data: Data) throws -> [StatBlock] {
        try JSONDecoder().decode(Payload.self, from: data).blocks
    }

    /// The blocks as plain text, one after another.
    public static func plainText(for blocks: [StatBlock]) -> String {
        blocks.map(StatBlockWriter.plainText).joined(separator: "\n\n")
    }

    /// Replaces the pasteboard's contents with the blocks, as stat block data and as plain text.
    public static func write(_ blocks: [StatBlock], to pasteboard: NSPasteboard) throws {
        let data = try data(for: blocks)
        pasteboard.clearContents()
        pasteboard.declareTypes([NSPasteboard.PasteboardType(typeIdentifier), .string], owner: nil)
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
        pasteboard.setString(plainText(for: blocks), forType: .string)
    }

    /// A drag of the blocks, offering the stat block data and plain text.
    public static func itemProvider(for blocks: [StatBlock]) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = (try? data(for: blocks)) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        let text = Data(plainText(for: blocks).utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier,
                                            visibility: .all) { completion in
            completion(text, nil)
            return nil
        }
        return provider
    }
}
