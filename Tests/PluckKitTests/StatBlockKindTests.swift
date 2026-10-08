import Foundation
@testable import PluckKit
import Testing

@Suite("Stat blocks other than creatures")
struct StatBlockKindTests {
    private typealias Page = TextPage

    /// Enough body text that its typeface, not the stat block's, is the document's main one.
    private static let bodyLines = (1...18).map { "Body text line number \($0)" } + ["and then it stops here."]

    /// A chase obstacle: underlined header, one labeled entry with a hanging line, a rule, then
    /// a description without a label.
    private func drawObstacle(on page: inout Page, type: String, underlined: Bool) {
        let left = Page.leftColumn
        page.line("INTO THE DRINK", x: left, top: 100, font: .display, size: 12)
        page.line(type, x: left + 150, top: 100, font: .display, size: 12)
        if underlined { page.rule(x: left, top: 103, width: 215) }
        page.line([("Chase Points", .display), (" 4; ", .sans), ("Overcome", .display), (" DC 17", .sans)],
                  x: left, top: 116)
        page.line("Acrobatics to sprint down the docks.", x: left + 9, top: 128, font: .sans)
        page.rule(x: left, top: 132, width: 215)
        page.lines(["The pirate has a head start", "and a long pier to reach her."], x: left, top: 142, font: .sans)
        page.lines(Self.bodyLines, x: Page.rightColumn, top: 100)
    }

    @Test("A chase obstacle is a stat block: a labeled entry, then its description after the rule")
    func chaseObstacle() throws {
        let blocks = try Page.blocks { drawObstacle(on: &$0, type: "OBSTACLE 1", underlined: true) }
        guard case .statBlock(let block) = try #require(blocks.first) else {
            Issue.record("not a stat block: \(blocks.map(\.summary))")
            return
        }
        #expect(block.level == "Obstacle 1" && block.displayName == "Into The Drink")
        #expect(block.entries.map(\.name) == ["Chase Points", ""])
        #expect(block.entries[0].text == "4; Overcome DC 17 Acrobatics to sprint down the docks.")
        #expect(block.entries[1].text == "The pirate has a head start and a long pier to reach her.")
        let yaml = TextRenderer(format: .markdown).render(blocks)
        #expect(yaml.contains("level: \"Obstacle 1\""))
        #expect(yaml.contains("""
            abilities_top:
              - name: ""
              - name: "Chase Points"
                desc: "4; __Overcome__ DC 17 Acrobatics to sprint down the docks."
              - name: ""
                desc: "The pirate has a head start and a long pier to reach her."
            """))
    }

    @Test("An unfamiliar type is a stat block only when its header is underlined")
    func unfamiliarType() throws {
        let underlined = try Page.blocks { drawObstacle(on: &$0, type: "VEHICLE 3", underlined: true) }
        let plain = try Page.blocks { drawObstacle(on: &$0, type: "VEHICLE 3", underlined: false) }

        #expect(underlined.first?.summary == "statblock:Into The Drink")
        #expect(!plain.contains { if case .statBlock = $0 { true } else { false } })
    }

    @Test("A hazard's Stealth takes the place of Perception, and Disable sits with its defences")
    func hazardFields() {
        let hazard = StatBlock(name: "SPIKED DOORFRAME", level: "Hazard 4", traits: ["MECHANICAL", "TRAP"], entries: [
            StatBlock.Entry(name: "Stealth", runs: [TextRun("DC 25 (trained)")]),
            StatBlock.Entry(name: "Description", runs: [TextRun("Spikes line the frame.")]),
            StatBlock.Entry(name: "Disable", runs: [TextRun("DC 20 Thievery")]),
            StatBlock.Entry(name: "AC", runs: [TextRun("21")])
        ])
        let yaml = StatBlockYAMLWriter(block: hazard).render()

        #expect(yaml.contains("modifier: 25\nperception:\n  - name: \"\"\n  - name: \"Stealth\""))
        #expect(yaml.contains("abilities_top:\n  - name: \"\"\n  - name: \"Description\""))
        #expect(yaml.contains("abilities_mid:\n  - name: \"\"\n  - name: \"Disable\""))
    }

    @Test("A description cut off by the end of the column is fetched from the next one")
    func descriptionInNextColumn() throws {
        let blocks = try Page.blocks { page in
            let left = Page.leftColumn
            page.lines(["Text in the block's own", "typeface fills the page", "above the obstacle here."],
                       x: left, top: 100, font: .sans)
            page.line("BEST DEALS IN TOWN", x: left, top: 690, font: .display, size: 12)
            page.line("OBSTACLE 1", x: left + 150, top: 690, font: .display, size: 12)
            page.rule(x: left, top: 693, width: 215)
            page.line([("Chase Points", .display), (" 2; ", .sans), ("Overcome", .display), (" DC 17.", .sans)],
                      x: left, top: 706)
            page.rule(x: left, top: 710, width: 215)
            page.lines(["An eager merchant insists", "the party buys something."], x: Page.rightColumn, top: 100,
                       font: .sans)
            page.lines(["More text follows after", "a blank line, set apart."], x: Page.rightColumn, top: 150,
                       font: .sans)
        }
        let block = try #require(blocks.compactMap { block -> StatBlock? in
            if case .statBlock(let statBlock) = block { statBlock } else { nil }
        }.first)
        #expect(block.entries.map(\.text) == [
            "2; Overcome DC 17.", "An eager merchant insists the party buys something."
        ])
        #expect(blocks.last?.summary == "p:More text follows after a blank line, set apart.")
    }
}
