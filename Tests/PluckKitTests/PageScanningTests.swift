import Foundation
@testable import PluckKit
import Testing

@Suite("Finding the images a page paints")
struct PageScanningTests {
    private func firstPixels(_ page: ExtractedPage) -> [[UInt8]] {
        page.rasters.map { Array($0.pixel(0, 0).prefix(3)) }
    }

    @Test("Images are reported in painting order")
    func paintingOrder() throws {
        let builder = PDFBuilder()
        let red = builder.addSolidImage(Color.red)
        let blue = builder.addSolidImage(Color.blue)
        builder.addPage(painting: [blue, red])

        #expect(try firstPixels(ExtractedPage(builder)) == [Color.blue, Color.red])
    }

    @Test("Images in the resources that the page never paints are ignored")
    func unusedResources() throws {
        let builder = PDFBuilder()
        let used = builder.addSolidImage(Color.red)
        let unused = builder.addSolidImage(Color.blue)
        builder.addPage(
            resources: "/XObject << /Used \(used) 0 R /Unused \(unused) 0 R >>",
            content: "q 50 0 0 50 0 0 cm /Used Do Q")

        #expect(try firstPixels(ExtractedPage(builder)) == [Color.red])
    }

    @Test("Images painted through nested form XObjects are found")
    func nestedForms() throws {
        let builder = PDFBuilder()
        let image = builder.addSolidImage(Color.green)
        let inner = builder.addStream(
            "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /XObject << /Im \(image) 0 R >> >>",
            data: Data("q 50 0 0 50 0 0 cm /Im Do Q".utf8))
        let outer = builder.addStream(
            "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /XObject << /Inner \(inner) 0 R >> >>",
            data: Data("/Inner Do".utf8))
        builder.addPage(resources: "/XObject << /Outer \(outer) 0 R >>", content: "/Outer Do /Outer Do")

        #expect(try firstPixels(ExtractedPage(builder)) == [Color.green])
    }

    @Test("A form without resources of its own uses the page's")
    func formInheritingResources() throws {
        let builder = PDFBuilder()
        let image = builder.addSolidImage(Color.blue)
        let form = builder.addStream(
            "/Type /XObject /Subtype /Form /BBox [0 0 100 100]", data: Data("q 50 0 0 50 0 0 cm /Im Do Q".utf8))
        builder.addPage(resources: "/XObject << /Fm \(form) 0 R /Im \(image) 0 R >>", content: "/Fm Do")

        #expect(try firstPixels(ExtractedPage(builder)) == [Color.blue])
    }

    @Test("Images inside tiling patterns are found")
    func tilingPattern() throws {
        let builder = PDFBuilder()
        let image = builder.addSolidImage(Color.red)
        let pattern = builder.addStream(
            """
            /Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 \
            /Resources << /XObject << /Im \(image) 0 R >> >>
            """,
            data: Data("q 10 0 0 10 0 0 cm /Im Do Q".utf8))
        builder.addPage(
            resources: "/Pattern << /P1 \(pattern) 0 R >>", content: "/Pattern cs /P1 scn 0 0 100 100 re f")

        #expect(try firstPixels(ExtractedPage(builder)) == [Color.red])
    }

    @Test("Inline images are extracted")
    func inlineImage() throws {
        var content = Data("q 50 0 0 50 0 0 cm BI /W 2 /H 1 /CS /RGB /BPC 8 ID ".utf8)
        content.append(Data(Color.red + Color.blue))
        content.append(Data(" EI Q".utf8))
        let builder = PDFBuilder()
        builder.addPage(resources: "", content: content)

        let image = try #require(try ExtractedPage(builder).rasters.first)
        #expect(image.pixel(0, 0) == Color.red + [255])
        #expect(image.pixel(1, 0) == Color.blue + [255])
    }

    @Test("A page without images yields nothing")
    func emptyPage() throws {
        let builder = PDFBuilder()
        builder.addPage(resources: "", content: "0 0 10 10 re f")

        let page = try ExtractedPage(builder)
        #expect(page.result.images.isEmpty)
        #expect(page.result.failureCount == 0)
    }

    @Test("Asking for an image the page does not paint reports which one")
    func missingOccurrence() throws {
        let builder = PDFBuilder()
        builder.addPage(painting: [builder.addSolidImage(Color.red)])
        let source = try PDFImageSource(url: builder.write())

        #expect(throws: PluckError.imageNotFound(page: 0, occurrence: 5)) {
            try source.loadImage(at: ImageLocator(pageIndex: 0, occurrenceIndex: 5))
        }
    }
}
