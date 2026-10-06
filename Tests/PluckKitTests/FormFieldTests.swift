import CoreGraphics
import Foundation
@testable import PluckKit
import Testing

@Suite("Reading filled-in form fields")
struct FormFieldTests {
    private typealias Page = TextPage

    // MARK: Images

    /// A widget whose normal appearance paints `image`; `entries` adds flags or states.
    private func widget(_ builder: PDFBuilder, appearance: String, entries: String = "") -> Int {
        builder.addObject("""
            << /Type /Annot /Subtype /Widget /FT /Btn /Rect [10 10 110 110] /F 4 \
            /AP << /N \(appearance) >> \(entries) >>
            """)
    }

    private func appearance(_ builder: PDFBuilder, painting image: Int) -> Int {
        builder.addStream(
            "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /XObject << /Im \(image) 0 R >> >>",
            data: Data("q 100 0 0 100 0 0 cm /Im Do Q".utf8))
    }

    private func firstPixels(_ builder: PDFBuilder) throws -> [[UInt8]] {
        try ExtractedPage(builder).rasters.map { Array($0.pixel(0, 0).prefix(3)) }
    }

    @Test("A picture placed in a form field is found after the page's own images")
    func imageInFieldAppearance() throws {
        let builder = PDFBuilder()
        let onPage = builder.addSolidImage(Color.red)
        let inField = builder.addSolidImage(Color.blue)
        let field = widget(builder, appearance: "\(appearance(builder, painting: inField)) 0 R")
        builder.addPage(
            resources: "/XObject << /Im \(onPage) 0 R >>", content: Data("q 50 0 0 50 0 0 cm /Im Do Q".utf8),
            options: PDFBuilder.PageOptions(annotations: [field]))

        #expect(try firstPixels(builder) == [Color.red, Color.blue])
    }

    @Test("A hidden annotation's appearance is not scanned")
    func hiddenAnnotation() throws {
        let builder = PDFBuilder()
        let image = builder.addSolidImage(Color.green)
        let field = widget(builder, appearance: "\(appearance(builder, painting: image)) 0 R", entries: "/F 2")
        builder.addPage(resources: "", content: Data(), options: PDFBuilder.PageOptions(annotations: [field]))

        #expect(try firstPixels(builder).isEmpty)
    }

    @Test("A button is scanned in the state it is shown in")
    func buttonState() throws {
        let builder = PDFBuilder()
        let shownState = appearance(builder, painting: builder.addSolidImage(Color.green))
        let otherState = appearance(builder, painting: builder.addSolidImage(Color.red))
        let states = "<< /On \(shownState) 0 R /Off \(otherState) 0 R >>"
        let shown = widget(builder, appearance: states, entries: "/AS /On")
        let stateless = widget(builder, appearance: states)
        builder.addPage(resources: "", content: Data(),
                        options: PDFBuilder.PageOptions(annotations: [shown, stateless]))

        #expect(try firstPixels(builder) == [Color.green])
    }

    // MARK: Text

    @Test("A field's value is body text, joined to the label it sits under, however large its font")
    func singleLineValue() throws {
        let blocks = try Page.blocks { page in
            page.line("Character Name", x: Page.leftColumn, top: 100)
            page.field("Eagan Norr", in: CGRect(x: Page.leftColumn, y: 104, width: 200, height: 18),
                       entries: "/DA (/Helv 14 Tf 0 g)")
            page.line("Ancestry", x: Page.leftColumn, top: 200)
        }
        #expect(blocks.map(\.summary) == ["p:Character Name Eagan Norr", "p:Ancestry"])
    }

    @Test("A multi-line field's value wraps to the field's width and keeps its line breaks")
    func multilineValue() throws {
        let blocks = try Page.blocks { page in
            page.field(
                "Retractable tech shield with a dent in the rim\\nCarried on the left arm",
                in: CGRect(x: Page.leftColumn, y: 100, width: 120, height: 80),
                entries: "/DA (/Helv 10 Tf 0 g) /Ff 4096")
        }
        #expect(blocks.map(\.summary) == [
            "p:Retractable tech shield with a dent in the rim Carried on the left arm"
        ])
    }

    @Test("Centered and right-aligned values are read in place", arguments: [1, 2])
    func alignedValue(alignment: Int) throws {
        let blocks = try Page.blocks { page in
            page.line("Armor Class", x: Page.leftColumn, top: 100)
            page.field(
                "18", in: CGRect(x: Page.leftColumn + 80, y: 90, width: 40, height: 14),
                entries: "/DA (/Helv 10 Tf 0 g) /Q \(alignment)")
        }
        #expect(blocks.map(\.summary) == ["p:Armor Class 18"])
    }

    @Test("A field that sizes its text automatically, or names no font, still yields its value")
    func automaticSize() throws {
        let blocks = try Page.blocks { page in
            page.field("Operative", in: CGRect(x: Page.leftColumn, y: 100, width: 120, height: 14),
                       entries: "/DA (/Helv 0 Tf 0 g)")
            page.field("Shield Bash and then a long stretch of further notes",
                       in: CGRect(x: Page.leftColumn, y: 200, width: 120, height: 60),
                       entries: "/Ff 4096")
        }
        #expect(blocks.map(\.summary).joined(separator: "|").contains("Operative"))
        #expect(blocks.map(\.summary).joined(separator: "|").contains("further notes"))
    }

    @Test("Empty and hidden fields contribute nothing")
    func emptyAndHidden() throws {
        let blocks = try Page.blocks { page in
            page.line("Notes", x: Page.leftColumn, top: 100)
            page.field("   ", in: CGRect(x: Page.leftColumn, y: 110, width: 200, height: 14))
            page.field("Secret", in: CGRect(x: Page.leftColumn, y: 130, width: 200, height: 14),
                       entries: "/DA (/Helv 10 Tf 0 g) /F 2")
        }
        #expect(blocks.map(\.summary) == ["p:Notes"])
    }
}
