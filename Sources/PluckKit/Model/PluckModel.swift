import AppKit
import Foundation
import Observation

/// The state of one Pluck window: the open PDF, its images, and what is selected.
@MainActor
@Observable
public final class PluckModel {
    /// What the main view shows: the PDF's images, or its text.
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case images
        case text

        public var id: String { rawValue }
    }

    public static let textFormatDefaultsKey = "textFormat"

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

    public var mode = Mode.images {
        didSet { if mode == .text { Task { await loadText() } } }
    }
    public var textFormat: TextFormat {
        didSet { defaults.set(textFormat.rawValue, forKey: Self.textFormatDefaultsKey) }
    }
    /// The text of each page extracted so far, by page index.
    public private(set) var pageTexts: [Int: [TextBlock]] = [:]
    public private(set) var isLoadingText = false
    /// The page the navigator has last been asked to bring into view.
    public private(set) var pageReveal: PageReveal?

    @ObservationIgnored private var source: PDFImageSource?
    @ObservationIgnored private var thumbnailer: PDFPageThumbnailer?
    /// Bumped on every open so a superseded scan can tell it should stop.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored private var password = ""

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        textFormat = defaults.string(forKey: Self.textFormatDefaultsKey).flatMap(TextFormat.init) ?? .markdown
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

    /// The pages whose text is shown: the selected ones, or all of them, in page order.
    public var textPageIndexes: [Int] {
        selectedPages.isEmpty ? Array(0..<pageCount) : selectedPages.sorted()
    }

    /// The text of the shown pages as blocks. Paragraphs cut by a page break are rejoined
    /// where the pages are consecutive.
    public var visibleTextBlocks: [TextBlock] {
        var runs: [[[TextBlock]]] = []
        var previousIndex: Int?
        for index in textPageIndexes {
            guard let blocks = pageTexts[index] else { continue }
            if let previousIndex, index == previousIndex + 1 {
                runs[runs.count - 1].append(blocks)
            } else {
                runs.append([blocks])
            }
            previousIndex = index
        }
        return runs.flatMap(TextFlow.join)
    }

    /// The text of the shown pages in the chosen format, one line per paragraph.
    public var visibleText: String {
        TextRenderer(format: textFormat, options: TextRenderOptions(defaults: defaults)).render(visibleTextBlocks)
    }

    /// A file name for exported text, such as `Scenario.md`.
    public var textFileName: String {
        let stem = documentURL?.deletingPathExtension().lastPathComponent ?? "text"
        return "\(stem).\(textFormat.fileExtension)"
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
            self.password = password
            pageCount = opened.0.pageCount
            phase = .scanning
            if mode == .text { Task { await loadText() } }
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

    /// Extracts the text of every page, a page at a time. Returns when done or superseded;
    /// calling it again once started does nothing.
    public func loadText() async {
        guard let url = documentURL, source != nil, !isLoadingText, pageTexts.isEmpty else { return }
        isLoadingText = true
        let loadGeneration = generation
        let password = password
        let textSource = try? await Task.detached { try PDFTextSource(url: url, password: password) }.value
        for pageIndex in 0..<(textSource?.pageCount ?? 0) {
            let blocks = await Task.detached { textSource?.blocks(forPageAt: pageIndex) ?? [] }.value
            guard loadGeneration == generation else { return }
            pageTexts[pageIndex] = blocks
        }
        if loadGeneration == generation { isLoadingText = false }
    }

    /// Asks the navigator to bring the selected image's page into view, without changing which
    /// pages are selected. An image used on several pages is shown on the first of them (among
    /// the selected pages, when there are any); asking again moves on to its next page.
    public func revealPageOfSelectedImage() {
        guard let image = selectedImages.first else { return }
        let shown = image.pageIndexes.filter { selectedPages.isEmpty || selectedPages.contains($0) }
        let pages = shown.isEmpty ? image.pageIndexes : shown
        let previous = pageReveal?.imageID == image.id ? pages.firstIndex(of: pageReveal?.pageIndex ?? -1) : nil
        let position = previous.map { ($0 + 1) % pages.count } ?? 0
        pageReveal = PageReveal(
            pageIndex: pages[position], imageID: image.id, sequence: (pageReveal?.sequence ?? 0) + 1)
        let place = pages.count > 1 ? " (\(position + 1) of the \(pages.count) pages with this image)" : ""
        statusMessage = "Page \(pages[position] + 1)\(place)"
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

    /// Puts the shown text on the pasteboard as a plain string in the chosen format.
    public func copyText(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(visibleText, forType: .string)
        statusMessage = "Copied text of \(Self.count(visibleTextPageCount, "page"))"
    }

    public func exportText(to url: URL) throws {
        try visibleText.write(to: url, atomically: true, encoding: .utf8)
        statusMessage = "Exported text to “\(url.lastPathComponent)”"
    }

    /// How many of the shown pages have had their text extracted.
    public var visibleTextPageCount: Int {
        textPageIndexes.count { pageTexts[$0] != nil }
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
        pageTexts = [:]
        pageReveal = nil
        isLoadingText = false
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

/// A request to bring a page into view in the navigator.
public struct PageReveal: Equatable, Sendable {
    public let pageIndex: Int
    /// The image whose page was asked for.
    let imageID: String
    /// Distinguishes a repeated request for the same page, so that it scrolls again.
    let sequence: Int
}
