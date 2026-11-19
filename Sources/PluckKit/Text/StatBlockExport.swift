import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Stat blocks on the pasteboard and in drags, for apps such as Turnkeeper that turn them into creatures.
///
/// The data is JSON, `{ "format": 1, "blocks": [StatBlock] }`, under the type
/// `io.github.scooper4711.pluck.statblock`. Each block keeps its name, level, traits, entries (bold label
/// plus styled runs, with action glyphs as tokens such as `[two-actions]`), subtier and source. HTML is
/// written alongside for rich-text apps, and plain text for every other app.
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

    /// The blocks as HTML for rich-text apps, with bold labels. The charset is declared because
    /// AppKit otherwise reads pasted HTML as Latin-1, garbling the action glyphs and dashes.
    public static func html(for blocks: [StatBlock]) -> String {
        let body = blocks.map { StatBlockWriter.pastedHTML($0, inline: HTMLWriter.inline) }
        return (["<meta charset=\"utf-8\">"] + body).joined(separator: "\n")
    }

    /// Replaces the pasteboard's contents with the blocks: one item as stat block data, HTML and plain text.
    @MainActor
    public static func write(_ blocks: [StatBlock], to pasteboard: any Pasteboard) throws {
        pasteboard.replaceContents(with: [[
            typeIdentifier: .data(try data(for: blocks)),
            UTType.html.identifier: .text(html(for: blocks)),
            UTType.utf8PlainText.identifier: .text(plainText(for: blocks))
        ]])
    }

    /// A drag of the blocks, offering the stat block data, HTML and plain text.
    public static func itemProvider(for blocks: [StatBlock]) -> NSItemProvider {
        let provider = NSItemProvider()
        register((try? data(for: blocks)) ?? Data(), as: typeIdentifier, in: provider)
        register(Data(html(for: blocks).utf8), as: UTType.html.identifier, in: provider)
        register(Data(plainText(for: blocks).utf8), as: UTType.utf8PlainText.identifier, in: provider)
        return provider
    }

    private static func register(_ data: Data, as type: String, in provider: NSItemProvider) {
        provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
    }
}
