import Foundation
@testable import PluckKit
import Testing

@Suite("Recognising Pathfinder stat blocks")
struct StatBlockTests {
    private typealias Page = TextPage

    /// Enough body text that its typeface, not the stat block's, is the document's main one.
    private static let bodyLines = (1...18).map { "Body text line number \($0)" } + ["and then it stops here."]

    /// Draws a compact stat block in the second typeface, starting at `top`, and returns the
    /// `top` of whatever follows it.
    @discardableResult
    private func drawGwibble(on page: inout Page, x: CGFloat, top: CGFloat) -> CGFloat {
        page.line("GWIBBLE", x: x, top: top, font: .display, size: 12)
        page.line("LEVEL 1", x: x + 170, top: top, font: .display, size: 12)
        page.line("UNIQUE LE SMALL FEY", x: x, top: top + 12, font: .display, size: 7)
        let entries: [[(String, Page.Font)]] = [
            [("Perception", .display), (" +6; darkvision", .sans)],
            [("Languages", .display), (" Undercommon", .sans)],
            [("Skills", .display), (" Acrobatics +7, Stealth +7", .sans)],
            [("Str", .display), (" -1, ", .sans), ("Dex", .display), (" +4, ", .sans), ("Con", .display),
             (" +1, ", .sans), ("Int", .display), (" -1, ", .sans), ("Wis", .display), (" +1, ", .sans),
             ("Cha", .display), (" +0", .sans)],
            [("Items", .display), (" darts (10), shortsword", .sans)],
            [("AC", .display), (" 16; ", .sans), ("Fort", .display), (" +5", .sans)],
            [("HP", .display), (" 23; ", .sans), ("Weaknesses", .display), (" cold iron 2", .sans)],
            [("Speed", .display), (" 20 feet; climb 20 feet", .sans)],
            [("Melee", .display), (" [one-action] shortsword +9 (agile),", .sans)]
        ]
        for (index, entry) in entries.enumerated() {
            page.line(entry, x: x, top: top + 26 + CGFloat(index) * Page.leading)
        }
        let last = top + 26 + CGFloat(entries.count) * Page.leading
        page.rule(x: x, top: top + 26 + 4.3 * Page.leading, width: 215)
        page.line([("Damage", .display), (" 1d6-1 piercing", .sans)], x: x + 9, top: last)
        return last + Page.leading
    }

    private func gwibble() throws -> StatBlock {
        let blocks = try Page.blocks { page in
            page.line("Encounter F (Subtier 1-2)", x: Page.leftColumn, top: 70, size: 13)
            page.lines(["Several mitflits wait in", "this cave, and they are", "not at all pleased to",
                        "see the party arrive."], x: Page.leftColumn, top: 100)
            let next = drawGwibble(on: &page, x: Page.leftColumn, top: 180)
            page.lines(["Body text carries on", "below the stat block."], x: Page.leftColumn, top: next + 30)
            page.lines(Self.bodyLines, x: Page.rightColumn, top: 100)
        }
        #expect(blocks.map(\.summary) == [
            "h3:Encounter F (Subtier 1-2)",
            "p:Several mitflits wait in this cave, and they are not at all pleased to see the party arrive.",
            "statblock:Gwibble (1-2)", "p:Body text carries on below the stat block.",
            "p:" + Self.bodyLines.joined(separator: " ")
        ])
        guard case .statBlock(let statBlock) = blocks[2] else { throw PluckError.noDocument(operation: "find it") }
        return statBlock
    }

    @Test("A stat block is read as name, level, traits and labelled entries")
    func structure() throws {
        let block = try gwibble()

        #expect(block.name == "GWIBBLE" && block.level == "Creature 1" && block.variant == "1-2")
        #expect(block.traits == ["UNIQUE", "LE", "SMALL", "FEY"])
        #expect(block.entries.map(\.name) == [
            "Perception", "Languages", "Skills", "Str", "Items", "AC", "HP", "Speed", "Melee"
        ])
        #expect(block.entry(named: "Melee")?.text == "[one-action] shortsword +9 (agile), Damage 1d6-1 piercing")
        #expect(block.sections.map { $0.map(\.name) } == [
            ["Perception", "Languages", "Skills", "Str", "Items"], ["AC", "HP"], ["Speed", "Melee"]
        ])
    }

    @Test("Markdown writes it as a Fantasy Statblocks block in the Basic Pathfinder 2e Layout")
    func markdown() throws {
        var block = try gwibble()
        block.source = "Pathfinder Society Scenario #1-02: The Mosquito Witch"

        #expect(TextRenderer(format: .markdown).render([.statBlock(block)]) == """
            ```statblock
            columns: 2
            forcecolumns: true
            layout: Basic Pathfinder 2e Layout
            source: "Pathfinder Society Scenario #1-02: The Mosquito Witch"
            name: "Gwibble (1-2)"
            level: "Creature 1"
            rare_03: [[Unique]]
            alignment: ""
            size: "Small"
            trait_01: [[evil]]
            trait_02: [[fey]]
            trait_03: [[lawful]]
            modifier: 6
            perception:
              - name: "Perception"
                desc: "+6; darkvision"
            languages: "Undercommon"
            skills:
              - name: "Skills"
                desc: "Acrobatics +7, Stealth +7"
            abilityMods: [-1, 4, 1, -1, 1, 0]
            sourcebook: "_Pathfinder Society Scenario #1-02: The Mosquito Witch_"
            speed: "20 feet; climb 20 feet"
            ac: 16
            armorclass:
              - name: AC
                desc: "16; __Fort__ +5"
            hp: 23
            health:
              - name: ""
              - name: HP
                desc: "23; __Weaknesses__ cold iron 2"
            abilities_top:
              - name: ""
              - name: "Items"
                desc: "darts (10), shortsword"
            abilities_mid:
              - name: ""
            attacks:
              - name: ""
              - name: "**Melee** `pf2:1` Shortsword"
                desc: "+9 (agile)\\n__Damage__ 1d6-1 piercing"
            ```
            """)
    }

    @Test("HTML writes it as a div with a heading, a trait list and a rule between sections")
    func html() throws {
        let html = TextRenderer(format: .html).render([.statBlock(try gwibble())])

        #expect(html.hasPrefix("""
            <div class="statblock">
            <h3>Gwibble (1-2) <span class="level">Creature 1</span></h3>
            <ul class="traits">
            <li>Unique</li>
            <li>LE</li>
            <li>Small</li>
            <li>Fey</li>
            </ul>
            <p><strong>Perception</strong> +6; darkvision</p>
            """))
        #expect(html.contains("<hr>\n<p><strong>AC</strong> 16; <strong>Fort</strong> +5</p>"))
        #expect(html.contains("<p><strong>Melee</strong> <span class=\"action\">◆</span> shortsword +9"))
        #expect(html.hasSuffix("</div>"))
    }

    @Test("Plain text lists the entries one per line")
    func plainText() throws {
        let text = TextRenderer(format: .plain).render([.statBlock(try gwibble())])
        #expect(text.hasPrefix("Gwibble (1-2) — Creature 1\nUnique, LE, Small, Fey\nPerception +6; darkvision\n"))
        #expect(text.hasSuffix("Melee ◆ shortsword +9 (agile), Damage 1d6-1 piercing"))
    }

    @Test("A stat block that carries on in the next column is kept in one piece")
    func acrossColumns() throws {
        let blocks = try Page.blocks { page in
            page.lines(Self.bodyLines, x: Page.leftColumn, top: 100)
            drawGwibble(on: &page, x: Page.leftColumn, top: 560)
            page.line([("Sneak Attack", .display), (" The mitflit deals 1d6", .sans)], x: Page.rightColumn, top: 100)
            page.line("extra precision damage.", x: Page.rightColumn + 9, top: 112, font: .sans)
            page.lines(["Body text resumes in", "the right column here."], x: Page.rightColumn, top: 160)
        }
        #expect(blocks.map(\.summary) == [
            "p:" + Self.bodyLines.joined(separator: " "), "statblock:Gwibble",
            "p:Body text resumes in the right column here."
        ])
        guard case .statBlock(let block) = blocks[1] else { return }
        #expect(block.entries.last?.name == "Sneak Attack")
        #expect(block.entries.last?.text == "The mitflit deals 1d6 extra precision damage.")
    }

    @Test("Entries pushed aside by an illustration still start new entries; inner labels do not")
    func wrappedAroundIllustration() throws {
        let blocks = try Page.blocks { page in
            page.lines(Self.bodyLines, x: Page.rightColumn, top: 100)
            let left = Page.leftColumn
            page.line("VOZ LIRAYNE", x: left, top: 100, font: .display, size: 12)
            page.line("CREATURE 5", x: left + 150, top: 100, font: .display, size: 12)
            page.line("UNIQUE NE MEDIUM", x: left, top: 112, font: .display, size: 7)
            page.line([("Perception", .display), (" +7", .sans)], x: left, top: 126)
            page.line([("Skills", .display), (" Arcana +13,", .sans)], x: left + 40, top: 138)
            page.line("Stealth +10", x: left + 42, top: 150, font: .sans)
            page.line([("AC", .display), (" 20, ", .sans), ("Fort", .display), (" +10,", .sans)],
                      x: left + 60, top: 162)
            page.line([("Will", .display), (" +9", .sans)], x: left + 50, top: 174)
            page.line([("HP", .display), (" 56", .sans)], x: left + 50, top: 186)
        }
        guard case .statBlock(let block) = try #require(blocks.first) else { return }
        #expect(block.entries.map(\.name) == ["Perception", "Skills", "AC", "HP"])
        #expect(block.entry(named: "Skills")?.text == "Arcana +13, Stealth +10")
        #expect(block.entry(named: "AC")?.text == "20, Fort +10, Will +9")
    }

    @Test("A blank line ends the stat block, even when the text after it looks like an entry")
    func blankLineEndsBlock() throws {
        let blocks = try Page.blocks { page in
            let left = Page.leftColumn
            page.line("CONVERTED KHEFAK", x: left, top: 100, font: .display, size: 12)
            page.line("CREATURE 2", x: left + 150, top: 100, font: .display, size: 12)
            page.line([("Perception", .display), (" +9; darkvision", .sans)], x: left, top: 114)
            page.line([("AC", .display), (" 16", .sans)], x: left, top: 126)
            page.line([("Impressed into Service:", .display), (" At the end of", .sans)], x: left + 9, top: 150)
            page.line("each round a delegate helps.", x: left, top: 162, font: .sans)
        }
        #expect(blocks.map(\.summary) == [
            "statblock:Converted Khefak", "p:Impressed into Service: At the end of each round a delegate helps."
        ])
    }

    @Test("A control character left after the name by the layout is not kept")
    func controlCharacterAfterName() throws {
        let blocks = try Page.blocks { page in
            page.lines(Self.bodyLines, x: Page.rightColumn, top: 100)
            page.line("DOCKHAND\u{8}", x: Page.leftColumn, top: 100, font: .display, size: 12)
            page.line("CREATURE 0", x: Page.leftColumn + 150, top: 100, font: .display, size: 12)
            page.line([("Perception", .display), (" +3", .sans)], x: Page.leftColumn, top: 114)
        }
        guard case .statBlock(let block) = try #require(blocks.first) else { return }
        #expect(block.name == "DOCKHAND")
        #expect(TextRenderer(format: .html).render(blocks).unicodeScalars.allSatisfy { $0.value >= 0x20 || $0 == "\n" })
    }

    @Test("An encounter roster shares the header line but is not a stat block")
    func encounterRoster() throws {
        let blocks = try Page.blocks { page in
            page.lines(Self.bodyLines, x: Page.rightColumn, top: 100)
            page.line("DOCKHAND (2)", x: Page.leftColumn, top: 100, font: .display, size: 12)
            page.line("CREATURE 0", x: Page.leftColumn + 150, top: 100, font: .display, size: 12)
            page.line("Page 11", x: Page.leftColumn, top: 114, font: .sans)
            page.line([("Initiative", .display), (" Perception +3", .sans)], x: Page.leftColumn, top: 126)
        }
        #expect(!blocks.contains { if case .statBlock = $0 { true } else { false } })
        #expect(blocks.first?.summary == "h3:DOCKHAND (2) CREATURE 0")
    }

    @Test("A line of description between the traits and the first entry is kept")
    func descriptionLine() throws {
        let blocks = try Page.blocks { page in
            page.lines(Self.bodyLines, x: Page.rightColumn, top: 100)
            let left = Page.leftColumn
            page.line("DWARF RIGGER", x: left, top: 100, font: .display, size: 12)
            page.line("CREATURE 1", x: left + 150, top: 100, font: .display, size: 12)
            page.line("MEDIUM DWARF HUMANOID", x: left, top: 112, font: .display, size: 7)
            page.line("Variant rigger (NPC Core 147)", x: left, top: 126, font: .sans)
            page.line([("Perception", .display), (" +10; darkvision", .sans)], x: left, top: 138)
            page.line([("AC", .display), (" 15", .sans)], x: left, top: 150)
        }
        guard case .statBlock(let block) = try #require(blocks.first) else { return }
        #expect(block.entries.map(\.name) == ["", "Perception", "AC"])
        #expect(block.entries.first?.text == "Variant rigger (NPC Core 147)")
    }

    @Test("Level labels are normalised, and negative levels keep their sign")
    func levels() {
        #expect(StatBlockParser.level(from: "LEVEL –1") == "Creature -1")
        #expect(StatBlockParser.level(from: "CREATURE 12") == "Creature 12")
        #expect(StatBlockParser.level(from: "HAZARD 3") == "Hazard 3")
    }
}
