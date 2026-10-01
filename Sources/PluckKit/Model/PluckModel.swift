import AppKit
import Foundation
import Observation

/// The state of one Pluck window: the open PDF, its images, and what is selected.
@MainActor
@Observable
public final class PluckModel {
    public enum Phase: Equatable {
        case empty
        case scanning
        case ready
        case passwordRequired(URL)
        case failed(String)
    }

    public private(set) var phase = Phase.empty
    public private(set) var documentURL: URL?
    public private(set) var pageCount = 0
    public private(set) var scannedPageCount = 0
    public private(set) var library = ImageLibrary()
    public private(set) var transforms: [String: ImageTransform] = [:]
    /// The outcome of the last copy or export, for the status bar.
    public var statusMessage = ""

    /// Pages picked in the navigator; empty shows the whole document.
    public var selectedPages: Set<Int> = []
    public var selectedImageIDs: Set<String> = []
    /// Hides images whose longest side is shorter than this many pixels.
    public var minimumDimension = 0

    @ObservationIgnored private var source: PDFImageSource?
    @ObservationIgnored private var thumbnailer: PDFPageThumbnailer?
    /// Bumped on every open so a superseded scan can tell it should stop.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Derived state

    public var visibleImages: [ExtractedImage] {
        library.images(onPages: selectedPages).filter { $0.longestSide >= minimumDimension }
    }

    /// Selected images that are currently shown, in display order.
    public var selectedImages: [ExtractedImage] {
        visibleImages.filter { selectedImageIDs.contains($0.id) }
    }

    public func transform(for image: ExtractedImage) -> ImageTransform {
        transforms[image.id] ?? .identity
    }

    // MARK: - Opening

    /// Opens a PDF and scans every page; returns once scanning finishes or is superseded.
    public func open(_ url: URL, password: String = "") async {
        generation += 1
        let openGeneration = generation
        reset(for: url)
        do {
            let opened = try await Task.detached {
                (try PDFImageSource(url: url, password: password),
                 try PDFPageThumbnailer(url: url, password: password))
            }.value
            guard openGeneration == generation else { return }
            (source, thumbnailer) = opened
            pageCount = opened.0.pageCount
            phase = .scanning
            await scanPages(of: opened.0, generation: openGeneration)
        } catch PluckError.passwordRequired {
            phase = .passwordRequired(url)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func pageThumbnail(at pageIndex: Int, maximumDimension: Int = 320) async -> CGImage? {
        guard let thumbnailer else { return nil }
        return await Task.detached {
            try? thumbnailer.thumbnail(ofPageAt: pageIndex, maximumDimension: maximumDimension)
        }.value
    }

    // MARK: - Editing

    /// Rotates or flips every selected image.
    public func apply(_ edit: ImageEdit) {
        for image in selectedImages {
            transforms[image.id] = transform(for: image).applying(edit)
        }
    }

    // MARK: - Output

    @discardableResult
    public func exportSelection(to directory: URL) async throws -> [URL] {
        try await export(selectedImages, to: directory)
    }

    @discardableResult
    public func exportVisible(to directory: URL) async throws -> [URL] {
        try await export(visibleImages, to: directory)
    }

    public func copySelection(to pasteboard: NSPasteboard = .general) async throws {
        let requests = try selectedImages.map { try renderRequest(for: $0) }
        let encoded = try await Task.detached { try PasteboardWriter.encode(requests) }.value
        PasteboardWriter.write(encoded, to: pasteboard)
        statusMessage = "Copied \(Self.count(encoded.count, "image"))"
    }

    /// The exporter configured from the user's WebP settings.
    public var exporter: ImageExporter {
        ImageExporter(options: WebPOptions(defaults: defaults))
    }

    /// Describes how to write one image out; `nil` once the image is gone.
    public func exportItem(forImageID id: String) -> ExportItem? {
        library.image(withID: id).flatMap { try? exportItem(for: $0) }
    }

    // MARK: - Private

    private func reset(for url: URL) {
        documentURL = url
        phase = .scanning
        pageCount = 0
        scannedPageCount = 0
        library = ImageLibrary()
        transforms = [:]
        selectedPages = []
        selectedImageIDs = []
        statusMessage = ""
        source = nil
        thumbnailer = nil
    }

    private func scanPages(of source: PDFImageSource, generation scanGeneration: Int) async {
        for pageIndex in 0..<source.pageCount {
            let result = await Task.detached { source.scanPage(at: pageIndex) }.value
            guard scanGeneration == generation else { return }
            library.add(result, pageIndex: pageIndex)
            scannedPageCount = pageIndex + 1
        }
        phase = .ready
    }

    private func export(_ images: [ExtractedImage], to directory: URL) async throws -> [URL] {
        let items = try images.map { try exportItem(for: $0) }
        let exporter = exporter
        let urls = try await Task.detached { try exporter.export(items, to: directory) }.value
        statusMessage = "Exported \(Self.count(urls.count, "image")) to “\(directory.lastPathComponent)”"
        return urls
    }

    private func exportItem(for image: ExtractedImage) throws -> ExportItem {
        let stem = documentURL?.deletingPathExtension().lastPathComponent ?? "image"
        let page = String(format: "%03d", (image.pageIndexes.first ?? 0) + 1)
        let ordinal = String(format: "%02d", image.locator.occurrenceIndex + 1)
        return ExportItem(request: try renderRequest(for: image), baseName: "\(stem)-p\(page)-\(ordinal)")
    }

    private func renderRequest(for image: ExtractedImage) throws -> RenderRequest {
        guard let source else { throw PluckError.noDocument(operation: "render an image") }
        return RenderRequest(source: source, locator: image.locator, transform: transform(for: image))
    }

    private static func count(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
