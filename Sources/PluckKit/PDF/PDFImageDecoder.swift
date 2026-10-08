import CoreGraphics
import Foundation
import ImageIO

/// The entries of an image dictionary every decoding path needs.
struct PDFImageInfo {
    /// Guards against absurd dimensions in a damaged file exhausting memory.
    private static let maximumPixelCount = 400_000_000

    let stream: PDFStream
    let dictionary: PDFDictionary
    let width: Int
    let height: Int
    /// A stencil carries one bit of coverage per pixel and no color of its own.
    let isStencil: Bool
    let bitsPerComponent: Int

    init(stream: PDFStream) throws {
        guard let dictionary = stream.dictionary,
              let width = dictionary.object("Width", "W")?.integer,
              let height = dictionary.object("Height", "H")?.integer,
              width > 0, height > 0, width * height <= Self.maximumPixelCount
        else { throw PluckError.unsupportedImage(reason: "missing or implausible dimensions") }
        self.stream = stream
        self.dictionary = dictionary
        self.width = width
        self.height = height
        isStencil = dictionary.object("ImageMask", "IM")?.bool ?? false
        bitsPerComponent = isStencil ? 1 : dictionary.object("BitsPerComponent", "BPC")?.integer ?? 8
    }
}

/// Decodes a PDF image stream, together with its masks, into a `RasterImage`.
struct PDFImageDecoder {
    var colorSpaceParser = PDFColorSpaceParser()

    func decode(_ stream: PDFStream) throws -> RasterImage {
        let info = try PDFImageInfo(stream: stream)
        if info.isStencil { return try stencilImage(info) }
        var image = try RasterImage(cgImage: baseImage(info))
        if let coverage = alphaCoverage(for: info, width: image.width, height: image.height) {
            image.multiplyAlpha(by: coverage)
        }
        return image
    }

    /// A stencil image is painted in the current fill color; on its own it is black on clear.
    private func stencilImage(_ info: PDFImageInfo) throws -> RasterImage {
        let plane = try RasterImage.grayPlane(of: baseImage(info), width: info.width, height: info.height)
        var pixels = Data(count: plane.count * RasterImage.bytesPerPixel)
        for (index, value) in plane.enumerated() {
            pixels[index * RasterImage.bytesPerPixel + 3] = 255 - value
        }
        return RasterImage(width: info.width, height: info.height, pixels: pixels)
    }

    /// The image's own pixels, before any mask stream is applied.
    private func baseImage(_ info: PDFImageInfo) throws -> CGImage {
        guard let (bytes, format) = info.stream.data() else {
            throw PluckError.unsupportedImage(reason: "unreadable stream data")
        }
        switch format {
        case .raw: return try rawImage(bytes, info)
        case .jpegEncoded:
            let image = try encodedImage(bytes)
            return fourColorImage(from: image, info) ?? image
        case .JPEG2000: return try encodedImage(bytes)
        @unknown default: throw PluckError.unsupportedImage(reason: "unknown stream encoding")
        }
    }

    private func encodedImage(_ bytes: CFData) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(bytes, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw PluckError.unsupportedImage(reason: "ImageIO cannot decode the JPEG data") }
        return image
    }

    /// ImageIO reads a four-color JPEG the way Photoshop writes one: an Adobe marker means the samples are
    /// stored inverted, so ImageIO flips them back. In a PDF the samples mean what they say unless the image's
    /// own `Decode` array inverts them, so the image is rebuilt from ImageIO's samples in the PDF's color space.
    /// Without this, such images come out as negatives. Nil leaves other images as ImageIO decoded them.
    private func fourColorImage(from decoded: CGImage, _ info: PDFImageInfo) -> CGImage? {
        guard decoded.colorSpace?.model == .cmyk, decoded.bitsPerComponent == 8, decoded.bitsPerPixel == 32,
              let space = try? colorSpace(of: info), space.componentCount == 4, !space.isInkAmount,
              let provider = decoded.dataProvider
        else { return nil }
        let decode = decodeArray(for: info, space: space)
        return CGImage(
            width: decoded.width, height: decoded.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: decoded.bytesPerRow, space: space.cgColorSpace, bitmapInfo: decoded.bitmapInfo,
            provider: provider, decode: decode.isEmpty ? nil : decode, shouldInterpolate: false,
            intent: .defaultIntent)
    }

    private func rawImage(_ bytes: CFData, _ info: PDFImageInfo) throws -> CGImage {
        let space = try colorSpace(of: info)
        let bitsPerPixel = info.bitsPerComponent * space.componentCount
        let bytesPerRow = (info.width * bitsPerPixel + 7) / 8
        guard CFDataGetLength(bytes) >= bytesPerRow * info.height else {
            throw PluckError.unsupportedImage(reason: "sample data is truncated or uses an unsupported filter")
        }
        let byteOrder: CGBitmapInfo = info.bitsPerComponent == 16 ? .byteOrder16Big : []
        let decode = decodeArray(for: info, space: space)
        guard let provider = CGDataProvider(data: bytes),
              let image = CGImage(
                width: info.width, height: info.height, bitsPerComponent: info.bitsPerComponent,
                bitsPerPixel: bitsPerPixel, bytesPerRow: bytesPerRow, space: space.cgColorSpace,
                bitmapInfo: byteOrder, provider: provider, decode: decode.isEmpty ? nil : decode,
                shouldInterpolate: false, intent: .defaultIntent)
        else { throw PluckError.unsupportedImage(reason: "Core Graphics rejects the sample layout") }
        return applyingColorKey(of: info, to: image)
    }

    private func colorSpace(of info: PDFImageInfo) throws -> PDFColorSpace {
        if info.isStencil { return PDFColorSpace(cgColorSpace: CGColorSpaceCreateDeviceGray()) }
        guard let object = info.dictionary.object("ColorSpace", "CS") else {
            throw PluckError.unsupportedImage(reason: "no color space")
        }
        return try colorSpaceParser.parse(object)
    }

    /// The `Decode` ranges to hand Core Graphics; empty means "use the color space's defaults".
    private func decodeArray(for info: PDFImageInfo, space: PDFColorSpace) -> [CGFloat] {
        let declared = info.dictionary.object("Decode", "D")?.array?.numbers ?? []
        let isUsable = declared.count == space.componentCount * 2
        guard space.isInkAmount else { return isUsable ? declared : [] }
        // More ink is darker, so the gray stand-in reads each range backwards.
        return isUsable ? [declared[1], declared[0]] : [1, 0]
    }

    /// A `Mask` array names a range of sample values that are fully transparent.
    private func applyingColorKey(of info: PDFImageInfo, to image: CGImage) -> CGImage {
        guard let ranges = info.dictionary.object("Mask")?.array?.numbers,
              ranges.count == image.bitsPerPixel / image.bitsPerComponent * 2,
              let keyed = image.copy(maskingColorComponents: ranges)
        else { return image }
        return keyed
    }

    /// Per-pixel opacity from a soft mask or stencil mask stream. A mask that cannot be decoded
    /// leaves the image opaque rather than losing the image.
    private func alphaCoverage(for info: PDFImageInfo, width: Int, height: Int) -> Data? {
        if let softMask = info.dictionary.object("SMask")?.stream {
            return try? grayPlane(of: softMask, width: width, height: height)
        }
        if let stencil = info.dictionary.object("Mask")?.stream {
            // A stencil paints where its samples are 0, the opposite of a soft mask.
            return (try? grayPlane(of: stencil, width: width, height: height)).map { Data($0.map { 255 - $0 }) }
        }
        return nil
    }

    private func grayPlane(of maskStream: PDFStream, width: Int, height: Int) throws -> Data {
        let mask = try baseImage(PDFImageInfo(stream: maskStream))
        return try RasterImage.grayPlane(of: mask, width: width, height: height)
    }
}
