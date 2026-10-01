import CoreGraphics
import Foundation
import PDFKit

/// Extracts structured text from one PDF. Safe to call from any thread; calls are serialised.
public final class PDFTextSource: @unchecked Sendable {
    /// How many pages are sampled to learn the body font and the running headers and footers.
    private static let sampleSize = 24
    /// Margin, as a share of the page height, in which a lone number is a page number.
    private static let pageNumberMargin: CGFloat = 0.08

    public let pageCount: Int

    private let document: PDFDocument
    private let graphicsDocument: CGPDFDocument
    private let lock = NSLock()
    private var contents: [Int: PageContent] = [:]
    private var blocks: [Int: [TextBlock]] = [:]
    private var profile: DocumentProfile?

    public init(url: URL, password: String = "") throws {
        graphicsDocument = try PDFDocumentOpener.open(url, password: password)
        guard let document = PDFDocument(url: url), !document.isLocked || document.unlock(withPassword: password)
        else { throw PluckError.cannotOpenDocument(url) }
        self.document = document
        pageCount = document.pageCount
    }

    /// The page's text as headings, paragraphs, list items and boxes, in reading order.
    public func blocks(forPageAt index: Int) -> [TextBlock] {
        lock.withLock {
            if let known = blocks[index] { return known }
            let result = autoreleasepool { makeBlocks(forPageAt: index) }
            blocks[index] = result
            contents[index] = nil
            return result
        }
    }

    private func makeBlocks(forPageAt index: Int) -> [TextBlock] {
        let profile = documentProfile()
        guard let content = content(ofPageAt: index) else { return [] }
        let fragments = content.fragments.filter { !profile.isRunningElement($0, on: content.size) }
        let flow = PageLayout(pageSize: content.size, body: profile.body)
            .flow(fragments: fragments, panels: content.panels, rules: content.rules)
        return ParagraphBuilder(body: profile.body, obstacles: content.images, compounds: profile.compounds)
            .blocks(from: flow)
    }

    private func documentProfile() -> DocumentProfile {
        if let profile { return profile }
        let step = max(1, pageCount / Self.sampleSize)
        let sample = stride(from: 0, to: pageCount, by: step).compactMap(content)
        let made = DocumentProfile(sample: sample, pageNumberMargin: Self.pageNumberMargin)
        profile = made
        return made
    }

    private func content(ofPageAt index: Int) -> PageContent? {
        if let known = contents[index] { return known }
        guard let page = document.page(at: index), let graphicsPage = graphicsDocument.page(at: index + 1)
        else { return nil }
        let graphics = PDFContentInterpreter.graphics(of: graphicsPage)
        let reader = PageTextReader(page: page, graphics: graphics)
        let content = PageContent(
            size: page.bounds(for: .cropBox).size, fragments: reader.fragments(),
            panels: (graphics.panels + graphics.images).map(reader.readingRect),
            images: graphics.images.map(reader.readingRect), rules: graphics.rules.map(reader.readingRect))
        contents[index] = content
        return content
    }
}

/// A page's raw material for layout, in reading coordinates.
struct PageContent {
    let size: CGSize
    let fragments: [TextFragment]
    /// Filled shapes and images: anything that could be the background of a box.
    let panels: [CGRect]
    let images: [CGRect]
    let rules: [CGRect]
}

/// What is true of the document as a whole: its body font, and the text repeated on every page.
struct DocumentProfile {
    private static let gridSize: CGFloat = 6
    private static let minimumRepeats = 3

    let body: BodyStyle
    /// Hyphenated words that appear unbroken somewhere in the sample, lower-cased.
    let compounds: Set<String>
    private let runningKeys: Set<String>
    private let pageNumberMargin: CGFloat

    init(sample: [PageContent], pageNumberMargin: CGFloat) {
        self.pageNumberMargin = pageNumberMargin
        var weights: [BodyStyle: Int] = [:]
        var repeats: [String: Int] = [:]
        var compounds: Set<String> = []
        for page in sample {
            for fragment in page.fragments {
                let style = fragment.style
                weights[BodyStyle(family: style.family, size: (style.size * 2).rounded() / 2), default: 0]
                    += fragment.characters.count
            }
            for key in Set(page.fragments.map(Self.key)) { repeats[key, default: 0] += 1 }
            compounds.formUnion(page.fragments.flatMap { Self.compounds(in: $0.text) })
        }
        self.compounds = compounds
        body = weights.max { $0.value < $1.value }?.key ?? BodyStyle(family: "", size: 10)
        let threshold = max(Self.minimumRepeats, sample.count * 3 / 10)
        runningKeys = Set(repeats.filter { $0.value >= threshold }.keys)
    }

    /// True for headers, footers and page numbers, which are not part of the page's text.
    func isRunningElement(_ fragment: TextFragment, on pageSize: CGSize) -> Bool {
        if runningKeys.contains(Self.key(for: fragment)) { return true }
        let isNumber = fragment.text.count <= 4 && fragment.text.allSatisfy(\.isNumber)
        let margin = pageSize.height * pageNumberMargin
        return isNumber && (fragment.frame.maxY < margin || fragment.frame.minY > pageSize.height - margin)
    }

    /// Words written with an internal hyphen, such as "mosquito-free".
    private static func compounds(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && $0 != "-" }
            .filter { $0.contains("-") && $0.first != "-" && $0.last != "-" }
            .map(String.init)
    }

    /// Identifies a fragment by rough position and text, with digits masked so that a page
    /// number in the same spot matches from page to page.
    private static func key(for fragment: TextFragment) -> String {
        let text = String(fragment.text.map { $0.isNumber ? "#" : $0 })
        let column = Int(fragment.frame.minX / gridSize)
        let row = Int(fragment.frame.minY / gridSize)
        return "\(column)|\(row)|\(text)"
    }
}
