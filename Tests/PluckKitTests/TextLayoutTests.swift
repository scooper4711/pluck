import Foundation
@testable import PluckKit
import Testing

@Suite("Reading text in the right order")
struct TextLayoutTests {
    private typealias Page = TextPage

    @Test("A paragraph's lines are joined into one line")
    func paragraphIsOneLine() throws {
        let blocks = try Page.blocks { page in
            page.lines(["The party walks into the", "village at dusk and finds", "the square empty."],
                       x: Page.leftColumn, top: 100)
        }
        #expect(blocks.map(\.summary) == ["p:The party walks into the village at dusk and finds the square empty."])
    }

    @Test("An indented line after a finished sentence starts a new paragraph")
    func indentStartsParagraph() throws {
        let blocks = try Page.blocks { page in
            let next = page.lines(["The first paragraph ends", "right here."], x: Page.leftColumn, top: 100)
            page.line("The second one is indented", x: Page.leftColumn + 12, top: next)
            page.line("and runs on to this line.", x: Page.leftColumn, top: next + Page.leading)
        }
        #expect(blocks.map(\.summary) == [
            "p:The first paragraph ends right here.",
            "p:The second one is indented and runs on to this line."
        ])
    }

    @Test("A gap between lines starts a new paragraph")
    func gapStartsParagraph() throws {
        let blocks = try Page.blocks { page in
            page.lines(["One block of text", "on two lines."], x: Page.leftColumn, top: 100)
            page.lines(["Another block", "further down."], x: Page.leftColumn, top: 150)
        }
        #expect(blocks.map(\.summary) == ["p:One block of text on two lines.", "p:Another block further down."])
    }

    @Test("Columns are read one after the other, not line by line across the page")
    func twoColumns() throws {
        let blocks = try Page.blocks { page in
            page.lines(["Left column line one", "left column line two", "left column line three."],
                       x: Page.leftColumn, top: 100)
            page.lines(["Right column line one", "right column line two", "right column line three."],
                       x: Page.rightColumn, top: 100)
        }
        #expect(blocks.map(\.summary) == [
            "p:Left column line one left column line two left column line three.",
            "p:Right column line one right column line two right column line three."
        ])
    }

    @Test("A paragraph that runs from one column into the next is rejoined")
    func paragraphAcrossColumns() throws {
        let blocks = try Page.blocks { page in
            page.lines(["A sentence that starts in", "the left column and then"], x: Page.leftColumn, top: 100)
            page.lines(["carries on in the right", "column until it ends."], x: Page.rightColumn, top: 100)
        }
        #expect(blocks.map(\.summary) == [
            "p:A sentence that starts in the left column and then carries on in the right column until it ends."
        ])
    }

    @Test("A full-width heading is read before the columns beneath it")
    func headingAboveColumns() throws {
        let blocks = try Page.blocks { page in
            page.line("Chapter One: The Road to Shimmerford", x: Page.leftColumn, top: 80, size: 18)
            page.lines(["Left text one", "left text two."], x: Page.leftColumn, top: 120)
            page.lines(["Right text one", "right text two."], x: Page.rightColumn, top: 120)
        }
        #expect(blocks.map(\.summary) == [
            "h2:Chapter One: The Road to Shimmerford", "p:Left text one left text two.",
            "p:Right text one right text two."
        ])
    }

    @Test("Larger type is a heading, with bigger type ranking higher")
    func headingLevels() throws {
        let blocks = try Page.blocks { page in
            page.line("Big Title", x: Page.leftColumn, top: 80, size: 24)
            page.line("Section", x: Page.leftColumn, top: 120, size: 13)
            page.line("Body text here.", x: Page.leftColumn, top: 150)
        }
        #expect(blocks.map(\.summary) == ["h1:Big Title", "h3:Section", "p:Body text here."])
    }

    @Test("A word broken across lines is mended, but a real hyphen is kept")
    func hyphenation() throws {
        let blocks = try Page.blocks { page in
            page.lines(["The villagers were terri-", "fied of the well-", "known witch."], x: Page.leftColumn, top: 100)
            page.lines(["She is well-known here."], x: Page.leftColumn, top: 200)
        }
        #expect(blocks.first?.summary == "p:The villagers were terrified of the well-known witch.")
    }

    @Test("Bold and italic runs are recovered from the fonts")
    func emphasis() throws {
        let blocks = try Page.blocks { page in
            page.line([("Treasure:", .bold), (" a vial of ", .regular), ("holy water", .italic), (".", .regular)],
                      x: Page.leftColumn, top: 100)
        }
        #expect(blocks == [.paragraph([
            TextRun("Treasure:", isBold: true), TextRun(" a vial of "), TextRun("holy water", isItalic: true),
            TextRun(".")
        ])])
    }

    @Test("A bold lead-in after a finished line starts a new paragraph")
    func boldLeadIn() throws {
        let blocks = try Page.blocks { page in
            page.line("Make the following changes.", x: Page.leftColumn, top: 100)
            page.line([("Subtier 1-2:", .bold), (" add one mitflit.", .regular)], x: Page.leftColumn, top: 112)
        }
        #expect(blocks.map(\.summary) == ["p:Make the following changes.", "p:Subtier 1-2: add one mitflit."])
    }
}
