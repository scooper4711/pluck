import AppKit
@testable import PluckKit
import Testing

@Suite("The system pasteboard", .enabled(if: DesktopSession.isAvailable, "It exists only in a desktop session"))
@MainActor
struct SystemPasteboardTests {
    @Test("Takes each item with its data and text forms, replacing what was there")
    func replaceContents() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.replaceContents(with: [["public.utf8-plain-text": .text("old")]])

        pasteboard.replaceContents(with: [
            ["public.png": .data(Data([1, 2, 3])), "public.utf8-plain-text": .text("Gwibble")],
            ["public.html": .text("<b>Gwibble</b>")]
        ])

        let items = try #require(pasteboard.pasteboardItems)
        #expect(items.count == 2)
        #expect(items[0].data(forType: .png) == Data([1, 2, 3]))
        #expect(items[0].string(forType: .string) == "Gwibble")
        #expect(items[1].string(forType: .html) == "<b>Gwibble</b>")
    }
}
