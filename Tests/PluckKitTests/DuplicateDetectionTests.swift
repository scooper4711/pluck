import Foundation
@testable import PluckKit
import Testing

@Suite("Detecting duplicate images")
struct DuplicateDetectionTests {
    private func library(for builder: PDFBuilder) throws -> ImageLibrary {
        let source = try PDFImageSource(url: builder.write())
        var library = ImageLibrary()
        for pageIndex in 0..<source.pageCount {
            library.add(source.scanPage(at: pageIndex), pageIndex: pageIndex)
        }
        return library
    }

    @Test("One image object painted on every page appears once, on all its pages")
    func sharedObject() throws {
        let builder = PDFBuilder()
        let border = builder.addSolidImage(Color.red)
        let photo = builder.addSolidImage(Color.blue)
        builder.addPage(painting: [border])
        builder.addPage(painting: [border, photo])
        builder.addPage(painting: [border])

        let library = try library(for: builder)
        #expect(library.images.map(\.pageIndexes) == [[0, 1, 2], [1]])
    }

    @Test("Separate objects with identical pixels are the same image, however they are stored")
    func identicalPixels() throws {
        let builder = PDFBuilder()
        let raw = builder.addRGBImage(width: 2, height: 1, samples: Color.red + Color.blue)
        let copy = builder.addRGBImage(width: 2, height: 1, samples: Color.red + Color.blue)
        let indexed = builder.addImage(
            width: 2, height: 1, entries: "/ColorSpace [/Indexed /DeviceRGB 1 <FF00000000FF>] /BitsPerComponent 8",
            data: Data([0, 1]))
        builder.addPage(painting: [raw])
        builder.addPage(painting: [copy])
        builder.addPage(painting: [indexed])

        let library = try library(for: builder)
        #expect(library.images.count == 1)
        #expect(library.images.first?.pageIndexes == [0, 1, 2])
    }

    @Test("An image painted twice on one page is listed once for that page")
    func repeatedOnPage() throws {
        let builder = PDFBuilder()
        let image = builder.addSolidImage(Color.green)
        builder.addPage(painting: [image, image])

        let library = try library(for: builder)
        #expect(library.images.map(\.pageIndexes) == [[0]])
        #expect(library.imageCount(onPage: 0) == 1)
    }

    @Test("Images that differ only in transparency are kept apart")
    func differingAlpha() throws {
        let builder = PDFBuilder()
        let mask = builder.addGrayImage(width: 1, height: 1, samples: [100])
        let opaque = builder.addRGBImage(width: 1, height: 1, samples: Color.red)
        let translucent = builder.addRGBImage(width: 1, height: 1, samples: Color.red, entries: "/SMask \(mask) 0 R")
        builder.addPage(painting: [opaque, translucent])

        #expect(try library(for: builder).images.count == 2)
    }

    @Test("Filtering by pages returns each matching image once, in order of first appearance")
    func pageFilter() throws {
        let builder = PDFBuilder()
        let border = builder.addSolidImage(Color.red)
        let first = builder.addSolidImage(Color.green)
        let second = builder.addSolidImage(Color.blue)
        builder.addPage(painting: [border, first])
        builder.addPage(painting: [border, second])
        builder.addPage(painting: [])

        let library = try library(for: builder)
        let ids = library.images.map(\.id)
        #expect(library.images(onPages: []).map(\.id) == ids)
        #expect(library.images(onPages: [0]).map(\.id) == [ids[0], ids[1]])
        #expect(library.images(onPages: [1]).map(\.id) == [ids[0], ids[2]])
        #expect(library.images(onPages: [0, 1]).map(\.id) == ids)
        #expect(library.images(onPages: [2]).isEmpty)
        #expect(library.image(withID: ids[2])?.pixelWidth == 4)
    }

    @Test("A shared image is decoded again correctly long after it was scanned")
    func reloadAfterScan() throws {
        let builder = PDFBuilder()
        let border = builder.addRGBImage(width: 2, height: 1, samples: Color.red + Color.blue)
        for _ in 0..<5 { builder.addPage(painting: [border]) }
        let source = try PDFImageSource(url: builder.write())
        let scanned = (0..<source.pageCount).flatMap { source.scanPage(at: $0).images }

        #expect(Set(scanned.map(\.id)).count == 1)
        let reloaded = try source.loadImage(at: try #require(scanned.last).locator)
        #expect(reloaded.contentHash == scanned.first?.id)
    }
}
