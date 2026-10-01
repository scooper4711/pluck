import CoreGraphics
import Foundation
import os

/// Where an image is painted: the n-th image occurrence on a page, in painting order.
public struct ImageLocator: Hashable, Sendable {
    public let pageIndex: Int
    public let occurrenceIndex: Int
}

/// What scanning one page found.
public struct PageScanResult: Sendable {
    public var images: [ExtractedImage] = []
    /// Images the page paints that could not be decoded.
    public var failureCount = 0
}

/// Extracts images from one PDF. Safe to call from any thread; calls are serialised.
public final class PDFImageSource: @unchecked Sendable {
    public static let thumbnailDimension = 400

    private static let logger = Logger(subsystem: "io.github.scooper4711.pluck", category: "extraction")

    public let pageCount: Int

    private let document: CGPDFDocument
    private let lock = NSLock()
    /// What each image stream decoded to (`nil` when it failed), so an image repeated across
    /// pages is decoded once. Stream pointers stay valid for the life of `document`.
    private var scannedStreams: [PDFStream: ExtractedImage?] = [:]

    public init(url: URL, password: String = "") throws {
        document = try PDFDocumentOpener.open(url, password: password)
        pageCount = document.numberOfPages
    }

    /// Finds, decodes and summarises every image painted by a page.
    public func scanPage(at pageIndex: Int) -> PageScanResult {
        lock.withLock {
            var result = PageScanResult()
            var occurrenceIndex = 0
            scan(pageIndex) { occurrence in
                let locator = ImageLocator(pageIndex: pageIndex, occurrenceIndex: occurrenceIndex)
                occurrenceIndex += 1
                if let image = self.summary(of: occurrence, at: locator) {
                    result.images.append(image)
                } else {
                    result.failureCount += 1
                }
            }
            return result
        }
    }

    /// Decodes the full-resolution pixels of a previously scanned image.
    public func loadImage(at locator: ImageLocator) throws -> RasterImage {
        try lock.withLock {
            var occurrenceIndex = 0
            var outcome: Result<RasterImage, Error>?
            scan(locator.pageIndex) { occurrence in
                if occurrenceIndex == locator.occurrenceIndex {
                    outcome = Result { try Self.decode(occurrence) }
                }
                occurrenceIndex += 1
            }
            guard let outcome else {
                throw PluckError.imageNotFound(page: locator.pageIndex, occurrence: locator.occurrenceIndex)
            }
            return try outcome.get()
        }
    }

    private func scan(_ pageIndex: Int, visit: @escaping (PDFImageOccurrence) -> Void) {
        guard let page = document.page(at: pageIndex + 1) else { return }
        autoreleasepool { PDFPageScanner.scan(page, visit: visit) }
    }

    private func summary(of occurrence: PDFImageOccurrence, at locator: ImageLocator) -> ExtractedImage? {
        if !occurrence.isInline, let known = scannedStreams[occurrence.stream] { return known }
        let image = Self.summarize(occurrence, at: locator)
        if !occurrence.isInline { scannedStreams[occurrence.stream] = .some(image) }
        return image
    }

    private static func summarize(_ occurrence: PDFImageOccurrence, at locator: ImageLocator) -> ExtractedImage? {
        do {
            let raster = try decode(occurrence)
            return ExtractedImage(
                id: raster.contentHash, pixelWidth: raster.width, pixelHeight: raster.height,
                thumbnail: try raster.makeThumbnail(maximumDimension: thumbnailDimension), locator: locator)
        } catch {
            logger.info("Skipped an image on page \(locator.pageIndex + 1): \(error.localizedDescription)")
            return nil
        }
    }

    private static func decode(_ occurrence: PDFImageOccurrence) throws -> RasterImage {
        let parser = PDFColorSpaceParser { occurrence.resource("ColorSpace", $0) }
        return try PDFImageDecoder(colorSpaceParser: parser).decode(occurrence.stream)
    }
}
