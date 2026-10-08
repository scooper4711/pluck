import AppKit
import Foundation
@testable import PluckKit
import Testing

/// The text workflows through the model the UI drives.
@MainActor
@Suite("Text mode workflows")
struct TextModelTests {
    private let defaults: UserDefaults
    private let model: PluckModel

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "PluckTests-\(UUID().uuidString)"))
        model = PluckModel(defaults: defaults)
    }

    /// Three pages; the paragraph on page 2 carries on to page 3.
    private func openSample() async throws {
        var first = TextPage()
        first.line("The Village", x: TextPage.leftColumn, top: 80, size: 18)
        first.lines(["Shimmerford is quiet", "at this hour."], x: TextPage.leftColumn, top: 120)
        var second = TextPage()
        second.lines(["The party sets out and", "walks through the"], x: TextPage.leftColumn, top: 100)
        var third = TextPage()
        third.lines(["misty woods until", "night falls."], x: TextPage.leftColumn, top: 100)
        let builder = PDFBuilder()
        [first, second, third].forEach { $0.add(to: builder) }
        await model.open(try builder.write(named: "Scenario"))
        await model.loadText()
    }

    @Test("Text is extracted for every page and shown as Markdown by default")
    func loadsText() async throws {
        try await openSample()

        #expect(model.pageTexts.count == 3 && !model.isLoadingText)
        #expect(model.textFormat == .markdown)
        #expect(model.visibleText == """
            ## The Village

            Shimmerford is quiet at this hour.

            The party sets out and walks through the misty woods until night falls.
            """)
    }

    @Test("Selecting pages narrows the text, and only neighboring pages are joined")
    func pageSelection() async throws {
        try await openSample()

        model.selectedPages = [1]
        #expect(model.visibleText == "The party sets out and walks through the")
        model.selectedPages = [0, 2]
        #expect(model.visibleTextBlocks.map(\.summary) == [
            "h2:The Village", "p:Shimmerford is quiet at this hour.", "p:misty woods until night falls."
        ])
        #expect(model.visibleTextPageCount == 2)
    }

    @Test("The format changes the markup and is remembered")
    func format() async throws {
        try await openSample()
        model.selectedPages = [0]

        model.textFormat = .html
        #expect(model.visibleText == "<h2>The Village</h2>\n<p>Shimmerford is quiet at this hour.</p>")
        model.textFormat = .plain
        #expect(model.visibleText == "The Village\n\nShimmerford is quiet at this hour.")
        #expect(PluckModel(defaults: defaults).textFormat == .plain)
        #expect(model.textFileName == "Scenario.txt")
    }

    @Test("Copy and export deliver the text shown")
    func copyAndExport() async throws {
        try await openSample()
        model.selectedPages = [0]
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        model.copyText(to: pasteboard)
        let url = try TemporaryDirectory.make().appendingPathComponent(model.textFileName)
        try model.exportText(to: url)

        #expect(pasteboard.string(forType: .string) == model.visibleText)
        #expect(try String(contentsOf: url, encoding: .utf8) == model.visibleText)
        #expect(model.statusMessage == "Exported text to “Scenario.md”")
    }

    @Test("Switching to text mode starts extraction, and reopening discards the old text")
    func modeAndReopen() async throws {
        try await openSample()
        #expect(model.mode == .images)
        model.mode = .text

        let builder = PDFBuilder()
        var page = TextPage()
        page.line("A different document.", x: TextPage.leftColumn, top: 100)
        page.add(to: builder)
        await model.open(try builder.write(named: "Other"))
        #expect(model.pageTexts.isEmpty || model.visibleText == "A different document.")
        await model.loadText()
        for _ in 0..<200 where model.pageTexts.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        #expect(model.visibleText == "A different document.")
    }
}
