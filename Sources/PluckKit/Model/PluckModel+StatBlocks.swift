import AppKit

/// The stat blocks on the shown pages, for copying into other apps such as Combat Pad.
extension PluckModel {
    /// The stat blocks on the shown pages, in reading order, including any set in boxes.
    public var visibleStatBlocks: [StatBlock] {
        Self.statBlocks(in: visibleTextBlocks)
    }

    nonisolated static func statBlocks(in blocks: [TextBlock]) -> [StatBlock] {
        blocks.flatMap { block -> [StatBlock] in
            switch block {
            case .statBlock(let statBlock): [statBlock]
            case .box(let box): statBlocks(in: box.blocks)
            default: []
            }
        }
    }

    /// Puts stat blocks on the pasteboard for apps such as Combat Pad, and as plain text for the rest.
    public func copyStatBlocks(_ blocks: [StatBlock], to pasteboard: NSPasteboard = .general) {
        do {
            try StatBlockExport.write(blocks, to: pasteboard)
            statusMessage = blocks.count == 1
                ? "Copied the stat block for \(blocks[0].displayName)"
                : "Copied \(Self.count(blocks.count, "stat block"))"
        } catch {
            statusMessage = "Copying the stat blocks failed: \(error.localizedDescription)"
        }
    }
}
