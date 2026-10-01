import CoreGraphics
import Foundation
import ImageIO
import libwebp
@testable import PluckKit
import UniformTypeIdentifiers

enum Color {
    static let red: [UInt8] = [255, 0, 0]
    static let green: [UInt8] = [0, 255, 0]
    static let blue: [UInt8] = [0, 0, 255]
    static let white: [UInt8] = [255, 255, 255]
    static let black: [UInt8] = [0, 0, 0]
}

extension RasterImage {
    /// The RGBA bytes of one pixel; `y` counts down from the top row.
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
        let offset = (y * width + x) * Self.bytesPerPixel
        return Array(pixels[offset..<offset + Self.bytesPerPixel])
    }

    var alphas: [UInt8] {
        stride(from: 3, to: pixels.count, by: Self.bytesPerPixel).map { pixels[$0] }
    }

    /// Builds an image from rows of RGBA pixels.
    init(rows: [[[UInt8]]]) {
        self.init(width: rows[0].count, height: rows.count, pixels: Data(rows.flatMap { $0.flatMap { $0 } }))
    }

    /// Decodes WebP with libwebp, which returns straight alpha exactly as stored.
    init(webP data: Data) throws {
        var width: Int32 = 0
        var height: Int32 = 0
        let decoded = data.withUnsafeBytes {
            WebPDecodeRGBA($0.bindMemory(to: UInt8.self).baseAddress, data.count, &width, &height)
        }
        guard let decoded else { throw PluckError.encodingFailed(format: "WebP", reason: "test decode failed") }
        defer { WebPFree(decoded) }
        self.init(
            width: Int(width), height: Int(height),
            pixels: Data(bytes: decoded, count: Int(width * height) * Self.bytesPerPixel))
    }

    init(encodedData data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw PluckError.encodingFailed(format: "image", reason: "test decode failed") }
        try self.init(cgImage: image)
    }
}

/// Whether two pixels match within a tolerance, for lossy or colour-managed paths.
func isClose(_ actual: [UInt8], _ expected: [UInt8], tolerance: Int = 12) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
}

enum Fixture {
    /// JPEG data for a solid-colour image.
    static func jpeg(color: [UInt8], width: Int, height: Int) throws -> Data {
        let pixels = Array(repeating: color + [255], count: width * height).flatMap { $0 }
        let image = try RasterImage(width: width, height: height, pixels: Data(pixels)).makeCGImage()
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A PDF encrypted by Core Graphics, containing one image.
    static func encryptedPDF(password: String) throws -> URL {
        let url = try TemporaryDirectory.make().appendingPathComponent("locked.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        let options = [kCGPDFContextUserPassword: password, kCGPDFContextOwnerPassword: "owner"] as CFDictionary
        let context = CGContext(url as CFURL, mediaBox: &mediaBox, options)!
        let image = try RasterImage(rows: [[Color.red + [255], Color.blue + [255]]]).makeCGImage()
        context.beginPDFPage(nil)
        context.draw(image, in: CGRect(x: 10, y: 10, width: 80, height: 40))
        context.endPDFPage()
        context.closePDF()
        return url
    }
}

/// The images extracted from the first page of a PDF, with their full-resolution pixels.
struct ExtractedPage {
    let result: PageScanResult
    let rasters: [RasterImage]

    init(_ builder: PDFBuilder, pageIndex: Int = 0) throws {
        let source = try PDFImageSource(url: builder.write())
        result = source.scanPage(at: pageIndex)
        rasters = try result.images.map { try source.loadImage(at: $0.locator) }
    }

    /// Builds a one-page PDF painting a single image and extracts it.
    static func single(_ addImage: (PDFBuilder) -> Int) throws -> ExtractedPage {
        let builder = PDFBuilder()
        builder.addPage(painting: [addImage(builder)])
        return try ExtractedPage(builder)
    }
}
