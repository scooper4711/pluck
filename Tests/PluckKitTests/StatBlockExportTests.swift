import AppKit
@testable import PluckKit
import Testing

@Suite("Copying stat blocks for other apps")
struct StatBlockExportTests {
    private let block = StatBlock(
        name: "GWIBBLE", level: "Creature 1", traits: ["UNIQUE", "SMALL", "FEY"],
        entries: [
            StatBlock.Entry(name: "Perception", runs: [TextRun(" +6; darkvision")]),
            StatBlock.Entry(name: "Melee", runs: [TextRun(" [one-action] "), TextRun("shortsword", isItalic: true),
                                                  TextRun(" +9 (agile), "), TextRun("Damage", isBold: true),
                                                  TextRun(" 1d6+2 piercing")])
        ],
        variant: "1-2", source: "Scenario #7-99")

    @Test("Stat blocks round-trip through their JSON, styling and all")
    func roundTrip() throws {
        let data = try StatBlockExport.data(for: [block])
        #expect(try StatBlockExport.blocks(from: data) == [block])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["format"] as? Int == 1)
    }

    @Test("The pasteboard gets the stat block type and plain text")
    func pasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PluckTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try StatBlockExport.write([block], to: pasteboard)
        let data = try #require(pasteboard.data(forType: NSPasteboard.PasteboardType(StatBlockExport.typeIdentifier)))
        #expect(try StatBlockExport.blocks(from: data).first?.displayName == "Gwibble (1-2)")
        #expect(pasteboard.string(forType: .string)?.hasPrefix("Gwibble (1-2) — Creature 1") == true)
    }

    @Test("Stat blocks are found in reading order, including those set in boxes")
    func findingBlocks() {
        let other = StatBlock(name: "TRAP", level: "Hazard 2", traits: [], entries: [])
        let blocks: [TextBlock] = [
            .paragraph([TextRun("Intro")]), .statBlock(block),
            .box(TextBox(kind: .sidebar, blocks: [.heading(level: 2, runs: [TextRun("Aside")]), .statBlock(other)]))
        ]
        #expect(PluckModel.statBlocks(in: blocks) == [block, other])
    }

    @Test("Copying reports what was copied")
    @MainActor
    func copyStatus() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PluckTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let model = PluckModel(defaults: try #require(UserDefaults(suiteName: "PluckTests-\(UUID().uuidString)")))
        model.copyStatBlocks([block], to: pasteboard)
        #expect(model.statusMessage == "Copied the stat block for Gwibble (1-2)")
        model.copyStatBlocks([block, block], to: pasteboard)
        #expect(model.statusMessage == "Copied 2 stat blocks")
    }

    @Test("A drag offers the stat block type and plain text")
    func drag() async throws {
        let provider = StatBlockExport.itemProvider(for: [block])
        #expect(provider.registeredTypeIdentifiers == [StatBlockExport.typeIdentifier, "public.utf8-plain-text"])
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: StatBlockExport.typeIdentifier) { data, error in
                if let data { continuation.resume(returning: data) } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
        #expect(try StatBlockExport.blocks(from: data) == [block])
    }
}
