import CoreGraphics
import Foundation
import ImageIO
import libwebp
import UniformTypeIdentifiers

/// How exported WebP files are compressed.
public struct WebPOptions: Equatable, Sendable {
    public static let losslessDefaultsKey = "exportLossless"
    public static let qualityDefaultsKey = "exportQuality"
    public static let defaultQuality = 90.0

    public var isLossless: Bool
    /// 0 (smallest) to 100 (best); ignored when lossless.
    public var quality: Double

    public init(isLossless: Bool = false, quality: Double = WebPOptions.defaultQuality) {
        self.isLossless = isLossless
        self.quality = min(100, max(0, quality))
    }

    public init(defaults: UserDefaults) {
        let hasQuality = defaults.object(forKey: Self.qualityDefaultsKey) != nil
        self.init(
            isLossless: defaults.bool(forKey: Self.losslessDefaultsKey),
            quality: hasQuality ? defaults.double(forKey: Self.qualityDefaultsKey) : Self.defaultQuality)
    }
}

public enum WebPEncoder {
    /// The largest width or height the WebP format can store.
    public static let maximumDimension = 16_383

    public static func encode(_ image: RasterImage, options: WebPOptions = WebPOptions()) throws -> Data {
        guard max(image.width, image.height) <= maximumDimension else {
            throw PluckError.encodingFailed(
                format: "WebP", reason: "\(image.width) × \(image.height) exceeds the format's 16383 pixel limit")
        }
        var output: UnsafeMutablePointer<UInt8>?
        let size = image.pixels.withUnsafeBytes { buffer in
            let rgba = buffer.bindMemory(to: UInt8.self).baseAddress
            let stride = Int32(image.width * RasterImage.bytesPerPixel)
            return options.isLossless
                ? WebPEncodeLosslessRGBA(rgba, Int32(image.width), Int32(image.height), stride, &output)
                : WebPEncodeRGBA(
                    rgba, Int32(image.width), Int32(image.height), stride, Float(options.quality), &output)
        }
        guard let output, size > 0 else {
            throw PluckError.encodingFailed(format: "WebP", reason: "libwebp produced no data")
        }
        defer { WebPFree(output) }
        return Data(bytes: output, count: size)
    }
}

public enum PNGEncoder {
    public static func encode(_ image: RasterImage) throws -> Data {
        try ImageIOEncoder.encode(image, as: .png)
    }
}

public enum TIFFEncoder {
    public static func encode(_ image: RasterImage) throws -> Data {
        try ImageIOEncoder.encode(image, as: .tiff)
    }
}

private enum ImageIOEncoder {
    static func encode(_ image: RasterImage, as type: UTType) throws -> Data {
        let data = NSMutableData()
        let name = type.preferredFilenameExtension?.uppercased() ?? type.identifier
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw PluckError.encodingFailed(format: name, reason: "ImageIO has no encoder for it")
        }
        CGImageDestinationAddImage(destination, try image.makeCGImage(), nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PluckError.encodingFailed(format: name, reason: "ImageIO could not write the image")
        }
        return data as Data
    }
}
