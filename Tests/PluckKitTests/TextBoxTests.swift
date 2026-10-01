import Foundation
@testable import PluckKit
import Testing

@Suite("Finding info boxes and page furniture")
struct TextBoxTests {
    private typealias Page = TextPage

    private func twoColumnPage(_ decorate: (inout Page) -> Void) throws -> [TextBlock] {
        try Page.blocks { page in
            page.lines(["Left column text one", "left column text two", "left column text three",
                        "left column text four", "left column text five", "left column text six."],
                       x: Page.leftColumn, top: 100)
            page.lines(["Right column starts", "above the box."], x: Page.rightColumn, top: 100)
            decorate(&page)
            page.lines(["Right column resumes", "below the box."], x: Page.rightColumn, top: 250)
        }
    }

    @Test("Text on a filled panel is a sidebar, kept whole and in its place in the column")
    func sidebar() throws {
        let blocks = try twoColumnPage { page in
            page.panel(x: Page.rightColumn - 8, top: 140, width: 220, height: 80)
            page.line("WHERE ON GOLARION?", x: Page.rightColumn, top: 160, font: .display, size: 12)
            page.lines(["The story takes place in", "the River Kingdoms."], x: Page.rightColumn, top: 180)
        }
        #expect(blocks.map(\.summary) == [
            "p:Left column text one left column text two left column text three left column text four "
                + "left column text five left column text six.",
            "p:Right column starts above the box.",
            "sidebar[h3:WHERE ON GOLARION? | p:The story takes place in the River Kingdoms.]",
            "p:Right column resumes below the box."
        ])
    }

    @Test("A passage between two rules is a callout")
    func callout() throws {
        let blocks = try twoColumnPage { page in
            page.rule(x: Page.rightColumn, top: 145, width: 200)
            page.lines(["Thank goodness you came!", "Do come inside."], x: Page.rightColumn, top: 165)
            page.rule(x: Page.rightColumn, top: 190, width: 200)
        }
        #expect(blocks.map(\.summary).contains("callout[p:Thank goodness you came! Do come inside.]"))
        #expect(blocks.last?.summary == "p:Right column resumes below the box.")
    }

    @Test("A callout that runs from the foot of one column to the head of the next is one passage")
    func calloutAcrossColumns() throws {
        let blocks = try Page.blocks { page in
            page.lines(["Body text in the left", "column runs for a few", "lines so that it is the",
                        "typeface most used", "and then it ends."], x: Page.leftColumn, top: 100)
            page.rule(x: Page.leftColumn, top: 640, width: 200)
            page.lines(["Greta looks around and", "asks what manner of"], x: Page.leftColumn, top: 660, font: .sans)
            page.lines(["madness just happened", "in the council hall."], x: Page.rightColumn, top: 100, font: .sans)
            page.rule(x: Page.rightColumn, top: 130, width: 200)
            page.lines(["Body text resumes in", "the right column here."], x: Page.rightColumn, top: 160)
        }
        #expect(blocks.map(\.summary) == [
            "p:Body text in the left column runs for a few lines so that it is the typeface most used "
                + "and then it ends.",
            "callout[p:Greta looks around and asks what manner of madness just happened in the council hall.]",
            "p:Body text resumes in the right column here."
        ])
    }

    @Test("Rules that separate the rows of a list do not make callouts")
    func rulesBetweenRows() throws {
        let blocks = try Page.blocks { page in
            for (index, name) in ["MITFLIT", "GWIBBLE", "BLOODSEEKER"].enumerated() {
                let top = 100 + CGFloat(index) * 50
                page.line(name, x: Page.leftColumn, top: top, font: .display, size: 12)
                page.rule(x: Page.leftColumn, top: top + 6, width: 200)
                page.line("Page 21; art on page 28", x: Page.leftColumn, top: top + 22)
            }
        }
        #expect(blocks.map(\.summary) == [
            "h3:MITFLIT", "p:Page 21; art on page 28", "h3:GWIBBLE", "p:Page 21; art on page 28",
            "h3:BLOODSEEKER", "p:Page 21; art on page 28"
        ])
    }

    @Test("A callout cut by a page break is put back together")
    func calloutAcrossPages() throws {
        var first = Page()
        first.lines(["Body text on page one", "runs for several lines", "so that its typeface is",
                     "the one most used", "which ends here."], x: Page.leftColumn, top: 100)
        first.rule(x: Page.leftColumn, top: 640, width: 200)
        first.lines(["A shaggy dog bolts down", "the street and a voice"], x: Page.leftColumn, top: 660, font: .sans)
        var second = Page()
        second.lines(["calls after it from far", "away in the fog."], x: Page.leftColumn, top: 100, font: .sans)
        second.rule(x: Page.leftColumn, top: 130, width: 200)
        second.lines(["Body text on page two", "also runs for a while", "before it finally stops",
                      "which ends here."], x: Page.leftColumn, top: 160)

        let joined = TextFlow.join(try Page.blocks(of: [first, second]))
        #expect(joined.map(\.summary) == [
            "p:Body text on page one runs for several lines so that its typeface is the one most used "
                + "which ends here.",
            "callout[p:A shaggy dog bolts down the street and a voice calls after it from far away in the fog.]",
            "p:Body text on page two also runs for a while before it finally stops which ends here."
        ])
    }

    @Test("Running headers, footers and page numbers are left out")
    func runningElements() throws {
        let words = ["Alpha", "Bravo", "Charlie", "Delta"]
        let pages = (1...4).map { number in
            var page = Page()
            page.line("The Mosquito Witch", x: 240, top: 40, font: .display, size: 14)
            page.lines(["\(words[number - 1]) is the word", "for \(words[4 - number])."], x: Page.leftColumn, top: 100)
            page.line("Pathfinder Society Scenario", x: 220, top: 760, font: .display)
            page.line("\(number)", x: 300, top: 778)
            return page
        }
        let blocks = try Page.blocks(of: pages)
        #expect(blocks.map { $0.map(\.summary) } == [
            ["p:Alpha is the word for Delta."], ["p:Bravo is the word for Charlie."],
            ["p:Charlie is the word for Bravo."], ["p:Delta is the word for Alpha."]
        ])
    }

    @Test("A paragraph cut by a page break is rejoined; a finished one is not")
    func paragraphAcrossPages() {
        let cut: [[TextBlock]] = [[.paragraph([TextRun("The party heads")])], [.paragraph([TextRun("north at dawn.")])]]
        let finished: [[TextBlock]] = [[.paragraph([TextRun("They rest.")])], [.paragraph([TextRun("Morning comes.")])]]

        #expect(TextFlow.join(cut).map(\.summary) == ["p:The party heads north at dawn."])
        #expect(TextFlow.join(finished).count == 2)
    }
}
