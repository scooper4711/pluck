import Accelerate
import CoreGraphics
import CryptoKit
import Foundation

/// An 8-bit sRGB bitmap with straight (non-premultiplied) alpha.
///
/// Pixels are stored top row first as tightly packed RGBA, which is the layout libwebp expects.
public struct RasterImage: Equatable, Sendable {
    public static let bytesPerPixel = 4

    public let width: Int
    public let height: Int
    public private(set) var pixels: Data

    public init(width: Int, height: Int, pixels: Data) {
        precondition(pixels.count == width * height * Self.bytesPerPixel, "RGBA pixel data must match the size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(cgImage: CGImage) throws {
        let isOpaqueGray = cgImage.colorSpace?.model == .monochrome && cgImage.isOpaque
        self = isOpaqueGray ? try Self.expandingGray(cgImage) : try Self.renderingColor(cgImage)
    }

    /// Identity of the decoded picture; two images with the same hash are duplicates.
    public var contentHash: String {
        var hasher = SHA256()
        withUnsafeBytes(of: (Int64(width), Int64(height))) { hasher.update(bufferPointer: $0) }
        hasher.update(data: pixels)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func makeCGImage() throws -> CGImage {
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * Self.bytesPerPixel, space: .standardRGB, bitmapInfo: bitmapInfo,
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw PluckError.renderingFailed(operation: "wrapping pixels in a CGImage") }
        return image
    }

    /// A display-sized copy whose longest side is at most `maximumDimension` pixels.
    public func makeThumbnail(maximumDimension: Int) throws -> CGImage {
        let scale = min(1, Double(maximumDimension) / Double(max(width, height)))
        let size = (width: max(1, Int(Double(width) * scale)), height: max(1, Int(Double(height) * scale)))
        guard let context = CGContext.rgba(width: size.width, height: size.height, data: nil) else {
            throw PluckError.renderingFailed(operation: "creating a thumbnail canvas")
        }
        context.interpolationQuality = .high
        context.draw(try makeCGImage(), in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let thumbnail = context.makeImage() else {
            throw PluckError.renderingFailed(operation: "creating a thumbnail")
        }
        return thumbnail
    }

    /// Scales every pixel's alpha by an 8-bit coverage plane of the same size.
    public mutating func multiplyAlpha(by coverage: Data) {
        precondition(coverage.count == width * height, "Coverage must have one byte per pixel")
        pixels.withUnsafeMutableBytes { (rgba: UnsafeMutableRawBufferPointer) in
            for (index, opacity) in coverage.enumerated() {
                let offset = index * Self.bytesPerPixel + 3
                let scaled = (Int(rgba[offset]) * Int(opacity) + 127) / 255
                rgba[offset] = UInt8(scaled)
            }
        }
    }

    /// Renders any image as an 8-bit gray plane, resampling it to the requested size.
    static func grayPlane(of image: CGImage, width: Int, height: Int) throws -> Data {
        var plane = Data(count: width * height)
        try plane.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { throw PluckError.renderingFailed(operation: "creating a gray canvas") }
            context.interpolationQuality = image.width == width && image.height == height ? .none : .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return plane
    }

    /// Gray images are expanded by hand so their sample values survive unchanged.
    private static func expandingGray(_ image: CGImage) throws -> RasterImage {
        let plane = try grayPlane(of: image, width: image.width, height: image.height)
        var pixels = Data(count: plane.count * bytesPerPixel)
        pixels.withUnsafeMutableBytes { (rgba: UnsafeMutableRawBufferPointer) in
            for (index, value) in plane.enumerated() {
                let offset = index * bytesPerPixel
                rgba[offset] = value
                rgba[offset + 1] = value
                rgba[offset + 2] = value
                rgba[offset + 3] = 255
            }
        }
        return RasterImage(width: image.width, height: image.height, pixels: pixels)
    }

    private static func renderingColor(_ image: CGImage) throws -> RasterImage {
        var pixels = Data(count: image.width * image.height * bytesPerPixel)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext.rgba(width: image.width, height: image.height, data: buffer.baseAddress)
            else { throw PluckError.renderingFailed(operation: "creating an RGBA canvas") }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            var premultiplied = vImage_Buffer(
                data: buffer.baseAddress, height: vImagePixelCount(image.height),
                width: vImagePixelCount(image.width), rowBytes: image.width * bytesPerPixel)
            vImageUnpremultiplyData_RGBA8888(&premultiplied, &premultiplied, vImage_Flags(kvImageNoFlags))
        }
        return RasterImage(width: image.width, height: image.height, pixels: pixels)
    }
}

extension CGColorSpace {
    static let standardRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
}

extension CGContext {
    /// An 8-bit premultiplied RGBA sRGB canvas; `data` may point at caller-owned storage.
    static func rgba(width: Int, height: Int, data: UnsafeMutableRawPointer?) -> CGContext? {
        CGContext(
            data: data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * RasterImage.bytesPerPixel, space: .standardRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

extension CGImage {
    var isOpaque: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: true
        default: false
        }
    }
}
