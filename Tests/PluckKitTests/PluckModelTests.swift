import AppKit
import Foundation
@testable import PluckKit
import Testing

/// End-to-end workflows through the model the UI drives.
@MainActor
@Suite("App workflows")
struct PluckModelTests {
    private let defaults: UserDefaults
    private let model: PluckModel

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "PluckTests-\(UUID().uuidString)"))
        defaults.set(true, forKey: WebPOptions.losslessDefaultsKey)
        model = PluckModel(defaults: defaults)
    }

    /// Three pages: a border on all of them, a wide red-then-blue picture on page 1,
    /// a translucent picture on page 2, and nothing else on page 3.
    private func openSample() async throws {
        let builder = PDFBuilder()
        let border = builder.addSolidImage(Color.green, width: 8, height: 8)
        let wide = builder.addRGBImage(width: 2, height: 1, samples: Color.red + Color.blue)
        let mask = builder.addGrayImage(width: 1, height: 1, samples: [128])
        let translucent = builder.addRGBImage(width: 1, height: 1, samples: Color.red, entries: "/SMask \(mask) 0 R")
        builder.addPage(painting: [border, wide])
        builder.addPage(painting: [border, translucent])
        builder.addPage(painting: [border])
        await model.open(try builder.write(named: "Sample"))
    }

    private var sizes: [String] { model.visibleImages.map { "\($0.pixelWidth)x\($0.pixelHeight)" } }

    private func select(width: Int) {
        model.selectedImageIDs = Set(model.visibleImages.filter { $0.pixelWidth == width }.map(\.id))
    }

    @Test("Opening a PDF scans every page and de-duplicates across them")
    func open() async throws {
        #expect(model.phase == .empty)
        try await openSample()

        #expect(model.phase == .ready)
        #expect(model.pageCount == 3 && model.scannedPageCount == 3)
        #expect(sizes == ["8x8", "2x1", "1x1"])
        #expect(model.library.imageCount(onPage: 2) == 1)
        #expect(await model.pageThumbnail(at: 0)?.width == 200)
    }

    @Test("Selecting pages narrows the images shown to those pages")
    func pageSelection() async throws {
        try await openSample()

        model.selectedPages = [0]
        #expect(sizes == ["8x8", "2x1"])
        model.selectedPages = [1]
        #expect(sizes == ["8x8", "1x1"])
        model.selectedPages = [0, 1]
        #expect(sizes == ["8x8", "2x1", "1x1"])
        model.selectedPages = [2]
        #expect(sizes == ["8x8"])
        model.selectedPages = []
        #expect(sizes == ["8x8", "2x1", "1x1"])
    }

    @Test("Selected images that are filtered out of view are not acted on")
    func hiddenSelection() async throws {
        try await openSample()
        select(width: 2)
        #expect(model.selectedImages.count == 1)

        model.selectedPages = [1]
        #expect(model.selectedImages.isEmpty)

        model.selectedPages = []
        model.minimumDimension = 4
        #expect(sizes == ["8x8"])
        #expect(model.selectedImages.isEmpty)
    }

    @Test("Edits apply to the selection only and carry through to exported WebP")
    func editAndExport() async throws {
        try await openSample()
        select(width: 2)
        model.apply(.rotateRight)
        let edited = try #require(model.selectedImages.first)
        #expect(model.transform(for: edited) == ImageTransform.identity.applying(.rotateRight))
        #expect(model.transforms.count == 1)

        let directory = try TemporaryDirectory.make()
        let urls = try await model.exportSelection(to: directory)

        #expect(urls.map(\.lastPathComponent) == ["Sample-p001-02.webp"])
        let exported = try RasterImage(webP: Data(contentsOf: urls[0]))
        #expect(exported.width == 1 && exported.height == 2)
        #expect(exported.pixel(0, 0) == Color.red + [255])
        #expect(exported.pixel(0, 1) == Color.blue + [255])
        #expect(model.statusMessage.hasPrefix("Exported 1 image to"))
    }

    @Test("Exporting everything shown keeps transparency and never overwrites")
    func exportVisible() async throws {
        try await openSample()
        model.selectedPages = [1]
        let directory = try TemporaryDirectory.make()

        let first = try await model.exportVisible(to: directory)
        let second = try await model.exportVisible(to: directory)

        #expect(first.map(\.lastPathComponent) == ["Sample-p001-01.webp", "Sample-p002-02.webp"])
        #expect(second.map(\.lastPathComponent) == ["Sample-p001-01-2.webp", "Sample-p002-02-2.webp"])
        #expect(try RasterImage(webP: Data(contentsOf: first[1])).pixel(0, 0) == Color.red + [128])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 4)
    }

    @Test("Copy puts each selected image on the pasteboard as PNG and TIFF with alpha")
    func copy() async throws {
        try await openSample()
        model.selectedImageIDs = Set(model.visibleImages.map(\.id))
        model.selectedPages = [1]
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        try await model.copySelection(to: pasteboard)

        let items = try #require(pasteboard.pasteboardItems)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.types.contains(.png) && $0.types.contains(.tiff) })
        let translucent = try RasterImage(encodedData: try #require(items[1].data(forType: .png)))
        #expect(translucent.pixel(0, 0) == Color.red + [128])
        #expect(model.statusMessage == "Copied 2 images")
    }

    @Test("A dragged image is described by an export item that writes its WebP file")
    func dragExportItem() async throws {
        try await openSample()
        let image = try #require(model.visibleImages.first)
        let item = try #require(model.exportItem(forImageID: image.id))
        let url = try TemporaryDirectory.make().appendingPathComponent(item.fileName)

        try model.exporter.write(item, to: url)

        #expect(item.fileName == "Sample-p001-01.webp")
        #expect(try RasterImage(webP: Data(contentsOf: url)).pixel(7, 7) == Color.green + [255])
        #expect(model.exportItem(forImageID: "missing") == nil)
    }

    @Test("A password-protected PDF asks for its password, then opens with it")
    func passwordProtected() async throws {
        let url = try Fixture.encryptedPDF(password: "secret")

        await model.open(url)
        #expect(model.phase == .passwordRequired(url))
        await model.open(url, password: "wrong")
        #expect(model.phase == .passwordRequired(url))
        await model.open(url, password: "secret")
        #expect(model.phase == .ready)
        #expect(model.visibleImages.count == 1)
    }

    @Test("A file that is not a PDF fails with an explanation")
    func notAPDF() async throws {
        let url = try TemporaryDirectory.make().appendingPathComponent("notes.pdf")
        try Data("plain text".utf8).write(to: url)

        await model.open(url)

        #expect(model.phase == .failed("Opening “notes.pdf” failed: it is not a readable PDF."))
        #expect(model.visibleImages.isEmpty)
    }

    @Test("Opening another PDF discards the previous document's state")
    func reopen() async throws {
        try await openSample()
        model.selectedPages = [0]
        select(width: 2)
        model.apply(.flipHorizontal)

        let builder = PDFBuilder()
        builder.addPage(painting: [builder.addSolidImage(Color.white, width: 3, height: 3)])
        await model.open(try builder.write(named: "Other"))

        #expect(sizes == ["3x3"])
        #expect(model.selectedPages.isEmpty && model.selectedImageIDs.isEmpty && model.transforms.isEmpty)
        #expect(model.documentURL?.lastPathComponent == "Other.pdf")
    }

    @Test("Copying or exporting with nothing open is a harmless no-op")
    func nothingOpen() async throws {
        let urls = try await model.exportVisible(to: try TemporaryDirectory.make())
        #expect(urls.isEmpty)
        model.apply(.rotateLeft)
        #expect(model.transforms.isEmpty)
    }
}
