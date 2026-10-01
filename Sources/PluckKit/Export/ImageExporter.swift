import Foundation

/// Everything needed to produce an image's final pixels away from the main thread.
public struct RenderRequest: Sendable {
    let source: PDFImageSource
    let locator: ImageLocator
    let transform: ImageTransform

    /// Decodes the full-resolution image and applies the user's rotation and flips.
    public func render() throws -> RasterImage {
        try transform.apply(to: source.loadImage(at: locator))
    }
}

/// An image to write out, with the file name (sans extension) it should get.
public struct ExportItem: Sendable {
    public let request: RenderRequest
    public let baseName: String

    public var fileName: String { "\(baseName).\(ImageExporter.fileExtension)" }
}

/// Writes images to disk as WebP.
public struct ImageExporter: Sendable {
    public static let fileExtension = "webp"

    public let options: WebPOptions

    public init(options: WebPOptions = WebPOptions()) {
        self.options = options
    }

    /// Writes every item into `directory`, never replacing an existing file.
    @discardableResult
    public func export(_ items: [ExportItem], to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try items.map { item in
            let url = Self.unusedURL(for: item.baseName, in: directory)
            try write(item, to: url)
            return url
        }
    }

    /// Writes one item to exactly `url`.
    public func write(_ item: ExportItem, to url: URL) throws {
        let data = try WebPEncoder.encode(item.request.render(), options: options)
        try data.write(to: url, options: .atomic)
    }

    private static func unusedURL(for baseName: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension(fileExtension)
            suffix += 1
        }
        return candidate
    }
}
