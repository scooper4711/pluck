import Foundation
@testable import PluckKit
import Testing

@Suite("Writing text as plain text, Markdown and HTML")
struct TextRendererTests {
    private static let blocks: [TextBlock] = [
        .heading(level: 2, runs: [TextRun("A. Shimmerford", isBold: true)]),
        .paragraph([TextRun("Treasure:", isBold: true), TextRun(" a vial of "),
                    TextRun("holy water ", isItalic: true), TextRun("& more <here>.")]),
        .listItem([TextRun("Tymon")]),
        .listItem([TextRun("Shimmerford")]),
        .box(TextBox(kind: .sidebar, blocks: [
            .heading(level: 3, runs: [TextRun("WHERE ON GOLARION?")]), .paragraph([TextRun("In the River Kingdoms.")])
        ])),
        .box(TextBox(kind: .callout, blocks: [.paragraph([TextRun("“Thank goodness you came!”")])]))
    ]

    @Test("Plain text has one line per paragraph and no markup")
    func plain() {
        #expect(TextRenderer(format: .plain).render(Self.blocks) == """
            A. Shimmerford

            Treasure: a vial of holy water & more <here>.

            • Tymon
            • Shimmerford

            WHERE ON GOLARION?

            In the River Kingdoms.

            “Thank goodness you came!”
            """)
    }

    @Test("Markdown marks headings, emphasis, lists and quotes boxes")
    func markdown() {
        #expect(TextRenderer(format: .markdown).render(Self.blocks) == """
            ## A. Shimmerford

            **Treasure:** a vial of *holy water* & more \\<here>.

            - Tymon
            - Shimmerford

            > ### WHERE ON GOLARION?
            >
            > In the River Kingdoms.

            > “Thank goodness you came!”
            """)
    }

    @Test("Markdown can write boxes as Obsidian callouts, titled by their heading")
    func obsidianCallouts() {
        let renderer = TextRenderer(format: .markdown, options: TextRenderOptions(usesObsidianCallouts: true))
        #expect(renderer.render(Array(Self.blocks.suffix(2))) == """
            > [!info] WHERE ON GOLARION?
            > In the River Kingdoms.

            > [!quote]
            > “Thank goodness you came!”
            """)
    }

    @Test("Markdown escapes text that would otherwise be read as markup")
    func markdownEscaping() {
        let blocks: [TextBlock] = [
            .paragraph([TextRun("1. Not a list, and 2*3 is not emphasis.")]),
            .paragraph([TextRun("# Not a heading")])
        ]
        #expect(TextRenderer(format: .markdown).render(blocks) == """
            1\\. Not a list, and 2\\*3 is not emphasis.

            \\# Not a heading
            """)
    }

    @Test("Action glyph tokens become symbols or codes, even when letter-spaced")
    func actionGlyphs() {
        let blocks: [TextBlock] = [.paragraph([
            TextRun("Swig", isBold: true), TextRun(" [ t w o - a c t i o n s ] drink, then [reaction] duck.")
        ])]
        #expect(TextRenderer(format: .plain).render(blocks) == "Swig ◆◆ drink, then ⤾ duck.")
        #expect(TextRenderer(format: .markdown).render(blocks) == "**Swig** `pf2:2` drink, then `pf2:r` duck.")
        #expect(TextRenderer(format: .html).render(blocks) == "<p><strong>Swig</strong> "
            + "<span class=\"action\">◆◆</span> drink, then <span class=\"action\">⤾</span> duck.</p>")
    }

    @Test("HTML wraps blocks in tags and escapes the text")
    func html() {
        #expect(TextRenderer(format: .html).render(Self.blocks) == """
            <h2>A. Shimmerford</h2>
            <p><strong>Treasure:</strong> a vial of <em>holy water</em> &amp; more &lt;here&gt;.</p>
            <ul>
            <li>Tymon</li>
            <li>Shimmerford</li>
            </ul>
            <div class="callout">
            <h3>WHERE ON GOLARION?</h3>
            <p>In the River Kingdoms.</p>
            </div>
            <blockquote>
            <p>“Thank goodness you came!”</p>
            </blockquote>
            """)
    }

    @Test("Each format has its own file extension and the option comes from user defaults")
    func formatsAndOptions() throws {
        #expect(TextFormat.allCases.map(\.fileExtension) == ["txt", "md", "html"])
        let defaults = try #require(UserDefaults(suiteName: "PluckTests-\(UUID().uuidString)"))
        #expect(!TextRenderOptions(defaults: defaults).usesObsidianCallouts)
        defaults.set(true, forKey: TextRenderOptions.obsidianCalloutsDefaultsKey)
        #expect(TextRenderOptions(defaults: defaults).usesObsidianCallouts)
    }
}
