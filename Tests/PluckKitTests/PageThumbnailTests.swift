import CoreGraphics
import Foundation
@testable import PluckKit
import Testing

@Suite("Drawing page thumbnails")
struct PageThumbnailTests {
    private static let white: [UInt8] = [255, 255, 255]
    private static let redSquare = Data("1 0 0 rg 0 0 100 100 re f".utf8)

    private func thumbnail(_ builder: PDFBuilder) throws -> RasterImage {
        let thumbnailer = try PDFPageThumbnailer(url: builder.write())
        return try RasterImage(cgImage: thumbnailer.thumbnail(ofPageAt: 0, maximumDimension: 200))
    }

    private func color(_ image: RasterImage, _ x: Int, _ y: Int) -> [UInt8] {
        Array(image.pixel(x, y).prefix(3))
    }

    @Test("What a form field shows is drawn on the page")
    func formFieldAppearance() throws {
        let builder = PDFBuilder()
        let appearance = builder.addStream(
            "/Type /XObject /Subtype /Form /BBox [0 0 100 100]", data: Self.redSquare)
        let field = builder.addFormField("""
            << /Type /Annot /Subtype /Widget /FT /Tx /T (name) /V (Eagan) /F 4 \
            /Rect [0 0 100 100] /AP << /N \(appearance) 0 R >> >>
            """)
        builder.addPage(resources: "", content: Data(), options: PDFBuilder.PageOptions(annotations: [field]))

        let image = try thumbnail(builder)
        #expect(color(image, 50, 150) == Color.red)
        #expect(color(image, 150, 50) == Self.white)
    }

    @Test("A rotated page is drawn upright, sized to its longer side")
    func rotatedPage() throws {
        let builder = PDFBuilder()
        builder.addPage(
            resources: "", content: Self.redSquare,
            options: PDFBuilder.PageOptions(mediaBox: "0 0 200 100", rotation: 90))

        let image = try thumbnail(builder)
        #expect(image.width == 100 && image.height == 200)
        // Turned a quarter clockwise, the page's left half ends up at the top.
        #expect(color(image, 50, 50) == Color.red)
        #expect(color(image, 50, 150) == Self.white)
    }

    @Test("A page whose box does not start at the origin is drawn from its corner")
    func offsetPage() throws {
        let builder = PDFBuilder()
        builder.addPage(
            resources: "", content: Data("1 0 0 rg 100 100 100 100 re f".utf8),
            options: PDFBuilder.PageOptions(mediaBox: "100 100 300 300"))

        let image = try thumbnail(builder)
        #expect(color(image, 50, 150) == Color.red)
        #expect(color(image, 150, 50) == Self.white)
    }

    @Test("A page that does not exist is reported as a rendering failure")
    func missingPage() throws {
        let builder = PDFBuilder()
        builder.addPage(resources: "", content: Data())
        let thumbnailer = try PDFPageThumbnailer(url: builder.write())

        #expect(throws: PluckError.self) { try thumbnailer.thumbnail(ofPageAt: 3, maximumDimension: 200) }
    }
}
